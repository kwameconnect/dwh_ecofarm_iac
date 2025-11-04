import pandas as pd
import boto3
from datetime import datetime
import logging
from awsglue.utils import getResolvedOptions
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

s3 = boto3.client("s3")
args = getResolvedOptions(sys.argv, ["PROC_BUCKET"])

bucket = args["PROC_BUCKET"]
key = "forecast_data/time_dim/time_dim.json"

# check if time_dim file already exists ---
try:
    s3.head_object(Bucket=bucket, Key=key)
    logger.info(f"time_dim file already exists at s3://{bucket}/{key}. Skipping creation.")
    
except s3.exceptions.ClientError as e:
    if e.response['Error']['Code'] == "404":
        logger.info("No existing time_dim found. Proceeding to create a new one.")

        # Define range for 2024–2026 hourly granularity
        start = pd.Timestamp("2024-01-01 00:00:00")
        end = pd.Timestamp("2026-12-31 23:00:00")
        hours = pd.date_range(start, end, freq='H')

        df = pd.DataFrame({
            "time_id": [d.strftime("%Y%m%d%H") for d in hours],
            "datetime": hours,
            "date": hours.date,
            "hour": hours.hour,
            "day": hours.day,
            "month": hours.month,
            "year": hours.year,
            "weekday_name": hours.day_name(),
            "is_weekend": hours.day_of_week >= 5
        })
        # Use direct string output
        json_str = df.to_json(orient="records", lines=True, date_format="iso")  # --- CHANGED: added date_format="iso" ---
        s3.put_object(
            Bucket=bucket, 
            Key=key, 
            Body=json_str.encode("utf-8"),
            ContentType="application/json"
        )

        logger.info(f"Uploaded time_dim with {len(df)} rows to s3://{bucket}/{key}")

    else:
        raise
