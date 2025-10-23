import boto3
import pandas as pd
import json
import os
from datetime import datetime, timezone
from io import StringIO
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Variables
s3 = boto3.client("s3")
RAW_BUCKET = os.environ["RAW_BUCKET"]

# Output folders
SOLAR_FACT_PATH = "uploads/measured/solar_fact/"
SOLAR_TIME_DIM_PATH = "uploads/measured/solar_time_dim/"
WATER_FACT_PATH = "uploads/measured/water_level_fact/"
WATER_TIME_DIM_PATH = "uploads/measured/water_level_time_dim/"

# Upload source folders
SOLAR_UPLOAD_PATH = "uploads/measured/upload/solar/"
RAIN_UPLOAD_PATH = "uploads/measured/upload/rainfall/"

# Metadata files for time ID tracking
SOLAR_META_PATH = "uploads/measured/metadata/solar_time_meta.json"
WATER_META_PATH = "uploads/measured/metadata/water_time_meta.json"


def get_last_id(bucket: str, key: str) -> int:
    """Read the last used ID from S3 metadata file, or start at 0 if not found."""
    try:
        response = s3.get_object(Bucket=bucket, Key=key)
        meta = json.loads(response["Body"].read().decode("utf-8"))
        return meta.get("last_id", 0)
    except s3.exceptions.NoSuchKey:
        logger.info(f"No metadata file found for {key}, counting IDs from 1.")
        return 0
    except Exception as e:
        logger.warning(f"Error reading metadata for {key}: {e}. Counting IDs from 1.")
        return 0


def update_last_id(bucket: str, key: str, last_id: int):
    """Update the metadata file in S3 with the latest ID value."""
    meta = {"last_id": last_id}
    s3.put_object(Bucket=bucket, Key=key, Body=json.dumps(meta).encode("utf-8"))
    logger.info(f"Updated metadata file {key} with last_id={last_id}")



def read_csv_from_s3(bucket: str, prefix: str):
    """Read all CSV files from an S3 prefix into a single Pandas DataFrame."""
    response = s3.list_objects_v2(Bucket=bucket, Prefix=prefix)
    if "Contents" not in response:
        return pd.DataFrame()

    frames = []
    for obj in response["Contents"]:
        key = obj["Key"]
        if not key.endswith(".csv"):
            continue
        csv_obj = s3.get_object(Bucket=bucket, Key=key)
        body = csv_obj["Body"].read().decode("utf-8")
        df = pd.read_csv(StringIO(body))
        frames.append(df)

    if frames:
        return pd.concat(frames, ignore_index=True)
    else:
        return pd.DataFrame()


def process_solar_data(df: pd.DataFrame, start_id: int):
    """Transform solar CSV data into fact and time dimension JSON lines."""
    if df.empty:
        return [], [], start_id

    fact_records = []
    time_records = []
    next_id = start_id

    for _, row in df.iterrows():
        next_id += 1
        timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
        date = datetime.strptime(str(row["date"]), "%Y-%m-%d")
        solarenergy_kwh = round(float(row["solarenergy_kwh"]), 2)

        time_record = {
            "solar_energy_time_id": next_id,
            "date": date.strftime("%Y-%m-%d"),
            "hour": date.hour,
            "day": date.day,
            "month": date.month,
            "year": date.year
        }

        fact_record = {
            "energy_id": next_id,
            "location_id": int(row.get("location_id", 1)),
            "energy_time_id": next_id,
            "solarenergy_kwh": solarenergy_kwh,
            "date_uploaded": timestamp
        }

        fact_records.append(fact_record)
        time_records.append(time_record)

    return fact_records, time_records, next_id


def process_water_data(df: pd.DataFrame, start_id: int):
    """Transform rainfall CSV data into fact and time dimension JSON lines."""
    if df.empty:
        return [], [], start_id

    fact_records = []
    time_records = []
    next_id = start_id

    for _, row in df.iterrows():
        next_id += 1
        timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
        date = datetime.strptime(str(row["date"]), "%Y-%m-%d")
        water_level_mm = int(row["water_level_mm"])
        rain_collected_mm = int(row["rain_collected_mm"])

        time_record = {
            "water_level_time_id": next_id,
            "date": date.strftime("%Y-%m-%d"),
            "hour": date.hour,
            "day": date.day,
            "month": date.month,
            "year": date.year
        }

        fact_record = {
            "water_level_id": next_id,
            "location_id": int(row.get("location_id", 1)),
            "level_time_id": next_id,
            "water_level_mm": water_level_mm,
            "rain_collected_mm": rain_collected_mm,
            "date_uploaded": timestamp
        }

        fact_records.append(fact_record)
        time_records.append(time_record)

    return fact_records, time_records, next_id


def write_json_lines_to_s3(bucket: str, prefix: str, records: list):
    """Write list of JSON records as line-delimited JSON file."""
    if not records:
        return

    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S")
    key = f"{prefix}{timestamp}.json"
    body = "\n".join(json.dumps(r) for r in records)
    s3.put_object(Bucket=bucket, Key=key, Body=body.encode("utf-8"))
    logger.info(f"Wrote {len(records)} records to s3://{bucket}/{key}")


def lambda_handler(event, context):
    """Main Lambda entry point."""
    logger.info("Starting measurement ingestion...")


    # Read last used IDs
    logger.info("Reading last IDs")
    last_solar_id = get_last_id(RAW_BUCKET, SOLAR_META_PATH)
    last_water_id = get_last_id(RAW_BUCKET, WATER_META_PATH)

    # Read CSV data
    logger.info("Reading CSV data from S3")
    solar_df = read_csv_from_s3(RAW_BUCKET, SOLAR_UPLOAD_PATH)
    water_df = read_csv_from_s3(RAW_BUCKET, RAIN_UPLOAD_PATH)

    # Process solar data
    logger.info("Processing solar data...")
    solar_fact, solar_time, last_solar_id = process_solar_data(solar_df, last_solar_id)
    write_json_lines_to_s3(RAW_BUCKET, SOLAR_FACT_PATH, solar_fact)
    write_json_lines_to_s3(RAW_BUCKET, SOLAR_TIME_DIM_PATH, solar_time)
    update_last_id(RAW_BUCKET, SOLAR_META_PATH, last_solar_id)

    # Process rainfall data
    logger.info("Processing rainfall data...")
    water_fact, water_time, last_water_id = process_water_data(water_df, last_water_id)
    write_json_lines_to_s3(RAW_BUCKET, WATER_FACT_PATH, water_fact)
    write_json_lines_to_s3(RAW_BUCKET, WATER_TIME_DIM_PATH, water_time)
    update_last_id(RAW_BUCKET, WATER_META_PATH, last_water_id)

    logger.info("Measurement ingestion complete.")
    return {"status": "success"}
