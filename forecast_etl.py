import boto3
import pandas as pd
import io
import os
from datetime import datetime, timezone

s3 = boto3.client("s3")

RAW_BUCKET = os.environ.get("RAW_BUCKET")
PROC_BUCKET = os.environ.get("PROC_BUCKET")
CHECKPOINT_KEY = "checkpoints/last_file.txt"


def get_last_checkpoint():
    try:
        obj = s3.get_object(Bucket=PROC_BUCKET, Key=CHECKPOINT_KEY)
        return obj["Body"].read().decode("utf-8").strip()
    except s3.exceptions.NoSuchKey:
        return None


def save_checkpoint(last_file_key):
    s3.put_object(
        Bucket=PROC_BUCKET,
        Key=CHECKPOINT_KEY,
        Body=last_file_key.encode("utf-8"),
    )


def clean_and_save(raw_key, last_file=False):
    # Download raw file
    raw_obj = s3.get_object(Bucket=RAW_BUCKET, Key=raw_key)
    df = pd.read_json(io.BytesIO(raw_obj["Body"].read()))

    # Drop nulls
    df_clean = df.dropna()

    # Partitioned output path by date
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    output_key = f"processed/date={today}/{os.path.basename(raw_key)}"

    # Save cleaned file
    buffer = io.BytesIO()
    df_clean.to_parquet(buffer, index=False)
    buffer.seek(0)

    s3.put_object(Bucket=PROC_BUCKET, Key=output_key, Body=buffer.getvalue())
    print(f"Processed and saved: {output_key}")


def main():
    # Get checkpoint
    last_checkpoint = get_last_checkpoint()

    # List all files in raw bucket
    response = s3.list_objects_v2(Bucket=RAW_BUCKET, Prefix="raw/")
    all_files = sorted([obj["Key"] for obj in response.get("Contents", [])])

    # If checkpoint exists, skip already processed files
    if last_checkpoint and last_checkpoint in all_files:
        start_index = all_files.index(last_checkpoint) + 1
        new_files = all_files[start_index:]
    else:
        new_files = all_files

    if not new_files:
        print("No new files to process.")
        return

    # Process new files
    for raw_key in new_files:
        clean_and_save(raw_key)

    # Update checkpoint to the last processed file
    save_checkpoint(new_files[-1])
    print(f"Updated checkpoint to: {new_files[-1]}")


if __name__ == "__main__":
    main()
