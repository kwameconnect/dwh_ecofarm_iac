import csv
import datetime
import boto3
import os
import logging
import json
from datetime import datetime, UTC, timezone

logger = logging.getLogger()
logger.setLevel(logging.INFO)
s3 = boto3.client('s3')
cloudwatch = boto3.client("cloudwatch")
raw_bucket = os.getenv("S3_RAW_BUCKET")

def publish_metric(metric_name, value, unit, location, forecast_date, forecast_hour):
    from datetime import datetime
    timestamp = datetime.strptime(forecast_date, "%Y-%m-%d").replace(hour=int(forecast_hour))
    cloudwatch.put_metric_data(
        Namespace="EcoFarm/Forecast",
        MetricData=[
            {
                "MetricName": metric_name,
                "Dimensions": [{"Name": "Location", "Value": location}],
                "Timestamp": timestamp,
                "Value": float(value),
                "Unit": "None"
            }
        ]
    )
    logger.info(f"Metric {metric_name}={value} at {timestamp} for {location}")


# List objects in the specified S3 bucket
def lambda_handler(event, context):
    bucket_name = raw_bucket
    prefix = "uploads/hist/"
    latitude = os.getenv("latitude")
    longitude = os.getenv("longitude")
    city = "Samsamso Ecofarm"
    country = "Ghana"

    # Download time metadata (for download_time_dim)
    
    # Location data (for location_dim)
    location_id = hash(f"{latitude}_{longitude}") % 1000000
    location_data = {
        "location_id": location_id,
        "city": city,
        "country": country,
        "latitude": latitude,
        "longitude": longitude
    }
    
    response = s3.list_objects_v2(Bucket=bucket_name, Prefix=prefix)

    for obj in response.get('Contents', []):
        key = obj['Key']

        # Skip the folder object itself, process JSON files only and log skipped objects
        if key.endswith('/') or not key.endswith('.json'):
            logger.info(f"Skipping non-JSON or folder object: {key}")
            continue
        logger.info(f"Processing JSON object {key}")

        # Get content from JSON object
        s3_object = s3.get_object(Bucket=bucket_name, Key=key)
        file_content = s3_object['Body'].read().decode('utf-8')

        # Skip invalid JSON files
        try:
            data = json.loads(file_content)
        except json.JSONDecodeError as e:
            logger.warning(f"Skipping invalid JSON file {key}: {e}")
            continue

        # Process the forecast structure
        if "days" not in data:
            logger.warning(f"Skipping {key}: missing 'days' field")
            continue

        # Prep download time metadata from LastModified
        last_modified = obj['LastModified']  # a datetime object (UTC)
        logger.info(f"Object: {key}, LastModified: {last_modified}")
        
        download_timestamp = last_modified.strftime("%Y-%m-%d %H:%M:%S")
        download_date = last_modified.strftime("%Y-%m-%d")
        download_hour = int(last_modified.strftime("%H"))
        download_day = int(last_modified.strftime("%d"))
        download_month = int(last_modified.strftime("%m"))
        download_year = int(last_modified.strftime("%Y"))
        download_time_id = hash(download_timestamp) % 1000000

        download_time_data = {
            "download_time_id": download_time_id,
            "timestamp": download_date,
            "hour": download_hour,
            "day": download_day,
            "month": download_month,
            "year": download_year
        }

        download_date_str = last_modified.strftime("%Y-%m-%dT%H:%M:%SZ")
        logger.info(f"Assigning download date {download_date_str} to {key}")

        # Process forecast data
        forecast_records = []
        for day in data["days"]:
            forecast_date = day["datetime"]
            forecast_day = int(datetime.strptime(forecast_date, "%Y-%m-%d").strftime("%d"))
            forecast_month = int(datetime.strptime(forecast_date, "%Y-%m-%d").strftime("%m"))
            forecast_year = int(datetime.strptime(forecast_date, "%Y-%m-%d").strftime("%Y"))

            for hour_data in day["hours"]:
                hour_str = hour_data["datetime"]
                hour = int(hour_str.split(":")[0])
                forecast_timestamp = f"{forecast_date} {hour_str}"
                forecast_time_id = hash(forecast_timestamp) % 1000000

               # Forecast time data (for forecast_time_dim)
                forecast_time_data = {
                    "forecast_time_id": forecast_time_id,
                    "date": f"{forecast_date}T{hour:02d}:00:00Z",
                    "hour": hour,
                    "day": forecast_day,
                    "month": forecast_month,
                    "year": forecast_year
                }

                # Forecast fact data (for forecast_fact table)
                forecast_record = {
                    "forecast_id": f"{location_id}_{forecast_time_id}_{context.aws_request_id}",
                    "location_id": location_id,
                    "time_id": forecast_time_id,
                    "temperature_c": float(hour_data["temp"]),
                    "rain_mm": float(hour_data["precip"]),
                    "solarradiation_w": float(hour_data["solarradiation"]),
                    "cloudcover": int(hour_data["cloudcover"]),
                    "wind_speed_kmh": float(hour_data["windspeed"]),
                    "humidity": float(hour_data["humidity"]),
                    "weather_condition": hour_data["conditions"]
                }
                forecast_records.append(forecast_record)

                # Publish CloudWatch metrics
                try:
                    publish_metric("TemperatureC", hour_data["temp"], "None", city, forecast_date, hour)
                    publish_metric("RainfallMM", hour_data["precip"], "Millimeters", city, forecast_date, hour)
                    publish_metric("SolarRadiationW", hour_data["solarradiation"], "Watts", city, forecast_date, hour)
                    publish_metric("WindSpeedKMH", hour_data["windspeed"], "Kilometers/Hour", city, forecast_date, hour)
                    publish_metric("Humidity", hour_data["humidity"], "Percent", city, forecast_date, hour)
                    publish_metric("CloudCover", hour_data["cloudcover"], "Percent", city, forecast_date, hour)
                except Exception as e:
                    logger.warning(f"Failed to send CloudWatch metric: {str(e)}")

                # Write forecast_time_dim data to S3 raw bucket
                try:
                    s3.put_object(
                        Bucket=raw_bucket,
                        Key=f"forecast_data/forecast_time_dim/{forecast_time_data['forecast_time_id']}.json",
                        Body=json.dumps(forecast_time_data)
                    )
                except Exception as e:
                    return {
                        "statusCode": 500,
                        "body": json.dumps({"error": f"S3 write failed for forecast_time: {str(e)}"})
                    }
                logger.info(f"Wrote forecast_time_dim for forecast_time_id: {forecast_time_data['forecast_time_id']}")
        # Write location_dim and download_time_dim data to S3 raw bucket
        try:
            s3.put_object(
                Bucket=raw_bucket,
                Key=f"forecast_data/location_dim/{location_data['location_id']}.json",
                Body=json.dumps(location_data)
            )
            logger.info(f"Wrote location_dim for location_id: {location_data['location_id']}")
            s3.put_object(
                Bucket=raw_bucket,
                Key=f"forecast_data/download_time_dim/{download_time_data['download_time_id']}.json",
                Body=json.dumps(download_time_data)
            )
            logger.info(f"Wrote download_time_dim for download_time_id: {download_time_data['download_time_id']}")
        except Exception as e:
            return {
                "statusCode": 500,
                "body": json.dumps({"error": f"S3 write failed for dimension data: {str(e)}"})
            }

    # Write forecast_fact data to S3 raw bucket
        try:
            for record in forecast_records:
                s3.put_object(
                    Bucket=raw_bucket,
                    Key=f"forecast_data/forecast_fact/{record['forecast_id']}.json",
                    Body=json.dumps(record)
                )
                logger.info(f"Wrote forecast_fact for forecast_id: {record['forecast_id']}")
        except Exception as e:
            return {
                "statusCode": 500,
                "body": json.dumps({"error": f"S3 write failed for forecast data: {str(e)}"})
            }

        return {
            "statusCode": 200,
            "body": json.dumps({"message": f"Successfully ingested {len(forecast_records)} forecast records"})
        }

        return {"statusCode": 200, "body": "Listed files successfully"}
    logger.info(f"Successfully ingested {len(forecast_records)} forecast records. json_ingest completed.")
