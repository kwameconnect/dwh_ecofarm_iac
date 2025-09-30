import boto3
import pandas as pd
import io
import os
import sys
import json
import logging
from datetime import datetime, timezone
from awsglue.utils import getResolvedOptions

# --- Configure logging (visible in CloudWatch) ---
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)
handler = logging.StreamHandler(sys.stdout)
formatter = logging.Formatter("%(asctime)s [%(levelname)s] %(message)s")
handler.setFormatter(formatter)
logger.addHandler(handler)

# --- Read Glue job arguments ---
args = getResolvedOptions(sys.argv, ["RAW_BUCKET", "PROC_BUCKET"])
RAW_BUCKET = args["RAW_BUCKET"]
PROC_BUCKET = args["PROC_BUCKET"]

# S3 client
s3 = boto3.client("s3")

# Checkpoint key inside processed bucket
CHECKPOINT_KEY = "checkpoints/last_file.txt"

# Mapping raw prefixes to processed target paths
PREFIX_MAP = {
    "download_time/": "forecast/download_time/",
    "forecast/": "forecast/forecast/",
    "forecast_time/": "forecast/forecast_time/",
    "location/": "forecast/location/",
}


def get_last_checkpoint():
    try:
        obj = s3.get_object(Bucket=PROC_BUCKET, Key=CHECKPOINT_KEY)
        checkpoint = obj["Body"].read().decode("utf-8").strip()
        logger.info(f"Loaded checkpoint: {checkpoint}")
        return checkpoint
    except s3.exceptions.NoSuchKey:
        logger.info("No checkpoint found. Processing all files in raw bucket.")
        return None


def save_checkpoint(last_file_key):
    s3.put_object(
        Bucket=PROC_BUCKET,
        Key=CHECKPOINT_KEY,
        Body=last_file_key.encode("utf-8"),
    )
    logger.info(f"Saved checkpoint: {last_file_key}")


def clean_and_save(raw_key):
    logger.info(f"Processing raw file: {raw_key}")

    # Download raw file
    raw_obj = s3.get_object(Bucket=RAW_BUCKET, Key=raw_key)
    raw_data = raw_obj["Body"].read()

    # Load JSON safely
    try:
        record = json.loads(raw_data)
    except json.JSONDecodeError as e:
        logger.error(f"Skipping {raw_key}, invalid JSON: {e}")
        return

    # Convert to DataFrame depending on structure
    if isinstance(record, dict):
        df = pd.DataFrame([record])
    elif isinstance(record, list):
        df = pd.DataFrame(record)
    else:
        logger.error(f"Unsupported JSON format in {raw_key}")
        return

    # Drop nulls
    before_rows = len(df)
    df_clean = df.dropna()
    after_rows = len(df_clean)
    logger.info(f"Cleaned data: dropped {before_rows - after_rows} null rows.")

    # Determine prefix mapping
    matched_prefix = None
    for raw_prefix, proc_prefix in PREFIX_MAP.items():
        if raw_key.startswith(raw_prefix):
            matched_prefix = proc_prefix
            break

    if not matched_prefix:
        logger.error(f"No target mapping found for {raw_key}")
        return

    # Partitioned output path by date
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    base_name = os.path.basename(raw_key).replace(".json", ".parquet")
    output_key = f"{matched_prefix}date={today}/{base_name}"

    # Save cleaned file as Parquet
    buffer = io.BytesIO()
    df_clean.to_parquet(buffer, index=False)
    buffer.seek(0)

    s3.put_object(Bucket=PROC_BUCKET, Key=output_key, Body=buffer.getvalue())
    logger.info(f"Processed and saved: {output_key}")


def main():
    logger.info("Starting ETL job...")

    # Get checkpoint
    last_checkpoint = get_last_checkpoint()

    # List all files in raw bucket
    all_files = []
    for prefix in PREFIX_MAP.keys():
        response = s3.list_objects_v2(Bucket=RAW_BUCKET, Prefix=prefix)
        if "Contents" in response:
            all_files.extend([obj["Key"] for obj in response["Contents"]])

    logger.info(f"Found {len(all_files)} files in raw bucket.")

    # If checkpoint exists, skip already processed files
    if last_checkpoint and last_checkpoint in all_files:
        start_index = all_files.index(last_checkpoint) + 1
        new_files = all_files[start_index:]
    else:
        new_files = all_files

    if not new_files:
        logger.info("No new files to process.")
        return

    # Process new files
    for raw_key in new_files:
        clean_and_save(raw_key)

    # Update checkpoint to the last processed file
    save_checkpoint(new_files[-1])
    logger.info(f"Updated checkpoint to: {new_files[-1]}")
    logger.info("ETL job finished successfully.")


if __name__ == "__main__":
    main()
