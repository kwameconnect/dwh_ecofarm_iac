import boto3
import pandas as pd
import os
import sys
import json
import logging
from io import StringIO
from datetime import datetime
from awsglue.utils import getResolvedOptions

# --- Logging setup ---
logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client("s3")

# --- Arguments and config ---
args = getResolvedOptions(sys.argv, ["RAW_BUCKET", "PROC_BUCKET"])
RAW_BUCKET = args["RAW_BUCKET"]
PROC_BUCKET = args["PROC_BUCKET"]
CHECKPOINT_FILE = os.environ.get("CHECKPOINT_FILE", "checkpoints/forecast_etl.json")

# These are your known raw data prefixes
RAW_PREFIXES = [
    "forecast_data/download_time_dim/",
    "forecast_data/forecast_fact/",
    "forecast_data/forecast_time_dim/",
    "forecast_data/location_dim/"
]

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
        Body=json.dumps(checkpoint_data).encode("utf-8"),
    )
    logger.info(f"Saved checkpoint: {checkpoint_data}")

# --- File listing ---
def list_new_files(prefix, last_checkpoint):
    """List files under a prefix that are newer than last checkpoint."""
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
    df = df.dropna(how="all")  # remove fully null rows
    after = len(df)
    if before != after:
        logger.info(f"[{key}] Dropped {before - after} all-null rows")

    return df

# --- Main ETL ---
def run_etl():
    checkpoint = load_checkpoint()
    new_checkpoint = checkpoint.copy()

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
                dfs.append(df)
            except Exception as e:
                logger.error(f"[ERROR] Failed to process {key}: {e}", exc_info=True)

        if dfs:
            combined = pd.concat(dfs, ignore_index=True)

            # Output file per run per dimension
            out_key = f"{prefix.rstrip('/')}/run_{datetime.utcnow().strftime('%Y%m%d%H%M%S')}.json"
            s3.put_object(
                Bucket=PROC_BUCKET,
                Key=out_key,
                Body=combined.to_json(orient="records", lines=True).encode("utf-8"),
            )
            logger.info(f"[INFO] Wrote processed file: {out_key} ({len(combined)} records)")

            # Update checkpoint with the newest last_modified
            latest_lm = max([lm for _, lm in new_files])
            new_checkpoint[prefix] = latest_lm

    save_checkpoint(new_checkpoint)
    logger.info("[INFO] Checkpoint updated.")

if __name__ == "__main__":
    run_etl()
