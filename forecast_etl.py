import boto3
import pandas as pd
import os
import sys
import json
from io import StringIO
from datetime import datetime
from awsglue.utils import getResolvedOptions

s3 = boto3.client("s3")

args = getResolvedOptions(sys.argv, ["RAW_BUCKET", "PROC_BUCKET"])
RAW_BUCKET = args["RAW_BUCKET"]
PROC_BUCKET = args["PROC_BUCKET"]
CHECKPOINT_FILE = os.environ.get("CHECKPOINT_FILE", "checkpoints/forecast_etl.json")

# These are your known raw data prefixes
RAW_PREFIXES = [
    "download_time/",
    "forecast/",
    "forecast_time/",
    "location/"
]


def load_checkpoint():
    try:
        obj = s3.get_object(Bucket=PROC_BUCKET, Key=CHECKPOINT_FILE)
        return json.loads(obj["Body"].read().decode("utf-8"))
    except s3.exceptions.NoSuchKey:
        print("[INFO] No checkpoint found. Scanning all files.")
        return {}
    except Exception as e:
        print(f"[WARN] Could not load checkpoint: {e}")
        return {}


def save_checkpoint(checkpoint_data):
    s3.put_object(
        Bucket=PROC_BUCKET,
        Key=CHECKPOINT_FILE,
        Body=json.dumps(checkpoint_data).encode("utf-8"),
    )


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
    return new_files


def process_file(key):
    """Download and return the file content as a DataFrame (assuming CSV)."""
    obj = s3.get_object(Bucket=RAW_BUCKET, Key=key)
    body = obj["Body"].read().decode("utf-8")
    return pd.read_csv(StringIO(body))


def run_etl():
    checkpoint = load_checkpoint()
    new_checkpoint = checkpoint.copy()

    for prefix in RAW_PREFIXES:
        print(f"[INFO] Checking prefix: {prefix}")
        new_files = list_new_files(prefix, checkpoint)

        if not new_files:
            print(f"[INFO] No new files for prefix {prefix}")
            continue

        dfs = []
        for key, lm in new_files:
            print(f"[INFO] Processing file: {key}")
            try:
                df = process_file(key)
                dfs.append(df)
            except Exception as e:
                print(f"[ERROR] Failed to process {key}: {e}")

        if dfs:
            combined = pd.concat(dfs, ignore_index=True)

            # Output file per run per dimension
            out_key = f"{prefix.rstrip('/')}/run_{datetime.utcnow().strftime('%Y%m%d%H%M%S')}.csv"
            csv_buf = StringIO()
            combined.to_csv(csv_buf, index=False)

            s3.put_object(
                Bucket=PROC_BUCKET,
                Key=out_key,
                Body=csv_buf.getvalue().encode("utf-8"),
            )
            print(f"[INFO] Wrote processed file: {out_key}")

            # Update checkpoint with the newest last_modified
            latest_lm = max([lm for _, lm in new_files])
            new_checkpoint[prefix] = latest_lm

    save_checkpoint(new_checkpoint)
    print("[INFO] Checkpoint updated.")


if __name__ == "__main__":
    run_etl()
