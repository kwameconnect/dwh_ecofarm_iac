import boto3
import pandas as pd
import os
import sys
import json
import logging
from io import StringIO
from datetime import datetime, timezone
from awsglue.utils import getResolvedOptions

# --- Logging setup ---
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Variables
s3 = boto3.client("s3")
args = getResolvedOptions(sys.argv, ["RAW_BUCKET", "PROC_BUCKET"])
RAW_BUCKET = args["RAW_BUCKET"]
PROC_BUCKET = args["PROC_BUCKET"]
CHECKPOINT_FILE = os.environ.get("CHECKPOINT_FILE", "checkpoints/forecast_etl.json")

  # Known raw data prefixes
RAW_PREFIXES = [
    "forecast_data/download_time_dim/",
    "forecast_data/forecast_fact/",
    "forecast_data/forecast_time_dim/",
    "forecast_data/location_dim/",
    #added paths to measured data
    "measured_data/solar_fact/",
    "measured_data/solar_time_dim/",
    "measured_data/water_level_fact/",
    "measured_data/water_level_time_dim/"
]

TIME_DIM_KEY = "forecast_data/time_dim/time_dim.json"

# --- Checkpoint helpers ---
def load_checkpoint():
    try:
        obj = s3.get_object(Bucket=PROC_BUCKET, Key=CHECKPOINT_FILE)
        checkpoint = json.loads(obj["Body"].read().decode("utf-8"))
        logger.info(f"Loaded checkpoint: {checkpoint}")
        return checkpoint
    except s3.exceptions.NoSuchKey:
        logger.info("No checkpoint found. Scanning all files.")
        return {}
    except Exception as e:
        logger.warning(f"Could not load checkpoint: {e}")
        return {}

def save_checkpoint(checkpoint_data):
    s3.put_object(
        Bucket=PROC_BUCKET,
        Key=CHECKPOINT_FILE,
        Body=json.dumps(checkpoint_data, sort_keys=True).encode("utf-8"),
    )
    logger.info(f"Saved checkpoint: {checkpoint_data}")

# --- File listing ---
def list_new_files(prefix, last_checkpoint):
    """List new files in S3 under the given prefix since the last checkpoint."""
    paginator = s3.get_paginator("list_objects_v2")
    page_iterator = paginator.paginate(Bucket=RAW_BUCKET, Prefix=prefix)
    new_files = []
    for page in page_iterator:
        for obj in page.get("Contents", []):
            key = obj["Key"]
            last_modified = obj["LastModified"].isoformat()
            if prefix not in last_checkpoint or last_modified > last_checkpoint[prefix]:
                new_files.append((key, last_modified))
    logger.info(f"[{prefix}] Found {len(new_files)} new files")
    return new_files

# --- File processor ---
def process_file(key):
    """Download and return the file content as a DataFrame (handles array, NDJSON, or single object)."""
    logger.info(f"Downloading {key} from {RAW_BUCKET}")
    obj = s3.get_object(Bucket=RAW_BUCKET, Key=key)
    body = obj["Body"].read().decode("utf-8")
    try:
        # First try: JSON array of objects
        df = pd.read_json(StringIO(body), lines=False)
        logger.info(f"[{key}] Parsed as JSON array")
    except ValueError:
        try:
            # Second try: NDJSON (one object per line)
            df = pd.read_json(StringIO(body), lines=True)
            logger.info(f"[{key}] Parsed as NDJSON")
        except ValueError:
            # Last try: Single JSON object
            data = json.loads(body)
            if isinstance(data, dict):
                df = pd.DataFrame([data])  # wrap into list so it's tabular
                logger.info(f"[{key}] Parsed as single JSON object")
            else:
                logger.error(f"[{key}] Unsupported JSON format: {type(data)}")
                raise

    before = len(df)
    # remove rows that are all null
    df = df.dropna(how="all")
    after = len(df)
    if before != after:
        logger.info(f"[{key}] Dropped {before - after} all-null rows")
    
    return df

# ---------- Add time_id column to time dimensions ---------- 
def add_time_id(df, prefix):
    """Adds a time_id column if year, month, day, and hour columns exist."""
    required_cols = ["year", "month", "day", "hour"]
    if all(col in df.columns for col in required_cols):
        # Ensure columns are integers and zero-padded properly before combining
        df["time_id"] = (
            df["year"].astype(int).astype(str).str.zfill(4) +
            df["month"].astype(int).astype(str).str.zfill(2) +
            df["day"].astype(int).astype(str).str.zfill(2) +
            df["hour"].astype(int).astype(str).str.zfill(2)
        ).astype(int)

        logger.info(f"[{prefix}] Added integer time_id from year, month, day, and hour.")
    else:
        logger.warning(f"[{prefix}] Missing one or more of year, month, day, hour columns; skipping time_id generation.")
    return df


# --- Load time_dim ---
def load_existing_time_dim():
    try:
        obj = s3.get_object(Bucket=PROC_BUCKET, Key=TIME_DIM_KEY)
        time_dim = pd.read_json(StringIO(obj["Body"].read().decode("utf-8")), lines=True)
        logger.info(f"Loaded existing time_dim with {len(time_dim)} records")
    except s3.exceptions.NoSuchKey:
        logger.info("No existing time_dim found; triggering Glue job to generate it...")
        
        glue = boto3.client("glue")
        job_name = "generate-time-dim"
        
        try:
            response = glue.start_job_run(JobName=job_name)
            run_id = response["JobRunId"]
            logger.info(f"Started Glue job '{job_name}' with run ID: {run_id}")
            
            # Optional: wait for the job to finish (synchronous wait)
            waiter = glue.get_waiter("job_run_succeeded")
            waiter.wait(JobName=job_name, RunId=run_id)
            logger.info(f"Glue job '{job_name}' completed successfully.")
            
            # Once done, reload the time_dim
            obj = s3.get_object(Bucket=PROC_BUCKET, Key=TIME_DIM_KEY)
            time_dim = pd.read_json(StringIO(obj["Body"].read().decode("utf-8")), lines=True)
            logger.info(f"loaded time_dim with {len(time_dim)} records")
        
        except Exception as e:
            logger.error(f"Failed to trigger or complete Glue job: {e}", exc_info=True)
            time_dim = pd.DataFrame(columns=["time_id", "datetime"])
    return time_dim

# --- Save time_dim as JSON ---
def save_time_dim(time_dim):
    s3.put_object(
        Bucket=PROC_BUCKET,
        Key=TIME_DIM_KEY,
        Body=time_dim.to_json(orient="records", lines=True, date_format="iso").encode("utf-8")
    )
    logger.info(f"Saved merged time_dim with {len(time_dim)} records")

# --- Main ETL ---
def run_etl():
    checkpoint = load_checkpoint()
    new_checkpoint = checkpoint.copy()

    # --- Load time dimension ---
    time_dim_df = load_existing_time_dim()
    
    for prefix in RAW_PREFIXES:
        logger.info(f"[INFO] Checking prefix: {prefix}")
        new_files = list_new_files(prefix, checkpoint)

        if not new_files:
            logger.info(f"[INFO] No new files for prefix {prefix}")
            continue
        dfs = []
        for key, lm in new_files:
            try:
                df = process_file(key)

                 # ---- 🔧 CAST TYPES TO MATCH GLUE SCHEMA ----
                if "time_id" in df.columns:
                    df["time_id"] = pd.to_numeric(df["time_id"], errors="coerce").astype("Int64")

                numeric_cols = ["year", "month", "day", "hour"]
                for col in numeric_cols:
                    if col in df.columns:
                        df[col] = pd.to_numeric(df[col], errors="coerce").astype("Int64")
        
                if "is_weekend" in df.columns:
                    df["is_weekend"] = df["is_weekend"].astype(bool)
        
                # Ensure datetime is actual datetime type
                if "datetime" in df.columns:
                    df["datetime"] = pd.to_datetime(df["datetime"], errors="coerce", utc=True)
        
                df = add_time_id(df, prefix)
                dfs.append(df)
        
            except Exception as e:
                logger.error(f"[ERROR] Failed to process {key}: {e}", exc_info=True)

        if dfs:
            dfs = [d for d in dfs if d is not None and not d.empty]
            if not dfs:
                logger.warning(f"No valid dataframes for prefix {prefix}; skipping concat.")
                continue

            combined = pd.concat(dfs, ignore_index=True)
            # --- CHANGED/NEW ---
            if "time_dim" in prefix and "time_id" in combined.columns:
                new_times = combined[["time_id"]].copy()
                if "datetime" in combined.columns:
                    new_times["datetime"] = combined["datetime"]
                else:
                    # fallback: use whichever column generated time_id
                    time_col = next((c for c in combined.columns if c.lower() in ["timestamp", "datetime", "time", "date_time"]), None)
                    if time_col:
                        new_times["datetime"] = combined[time_col]
                time_dim_df = pd.concat([time_dim_df, new_times], ignore_index=True).drop_duplicates("time_id")
                logger.info(f"[{prefix}] Merged {len(new_times)} new time_dim records.")



            # Output file per run per dimension
              # !!! >= python 3.9 !!! added '.removeprefix('measured_data/')' for measured paths
            out_key = f"{prefix.rstrip('/')}/{prefix.removeprefix('forecast_data/').removeprefix('measured_data/').rstrip('/')}_{datetime.now(timezone.utc).strftime('%Y%m%d%H%M')}.json"
            s3.put_object(
                Bucket=PROC_BUCKET,
                Key=out_key,
                Body=combined.to_json(orient="records", lines=True, date_format="iso").encode("utf-8"),
            )
            logger.info(f"[INFO] Wrote processed file: {out_key} ({len(combined)} records)")

            # Update checkpoint with the newest last_modified
            latest_lm = max([lm for _, lm in new_files])
            new_checkpoint[prefix] = latest_lm

    if not time_dim_df.empty:
        save_time_dim(time_dim_df)
        logger.info("Updated time_dim saved.")

    save_checkpoint(new_checkpoint)
    logger.info("Checkpoint updated.")

if __name__ == "__main__":
    run_etl()
