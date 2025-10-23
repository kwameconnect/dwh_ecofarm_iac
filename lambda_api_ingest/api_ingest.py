# /iac/lambda_code/API_ingest.py: downloads api response to S3 raw_bucket as facts and dimensions in json files 
import logging
import json
import os
import boto3
import requests
from datetime import datetime, UTC, timezone

logger = logging.getLogger()
logger.setLevel(logging.INFO)
s3 = boto3.client("s3")
cloudwatch = boto3.client("cloudwatch")

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

def lambda_handler(event, context):
    # Configuration from environment variables
    api_key = os.getenv("VISUALCROSSING_API_KEY")
    raw_bucket = os.getenv("S3_RAW_BUCKET")
    latitude = os.getenv("latitude")
    longitude = os.getenv("longitude")
    city = "Samsamso Ecofarm"
    country = "Ghana"
    url = f"https://weather.visualcrossing.com/VisualCrossingWebServices/rest/services/timeline/{latitude}%2C{longitude}/today?unitGroup=metric&include=days%2Chours&key={api_key}&contentType=json"

    # Make API request
    try:
        response = requests.get(url, timeout=10)
        if response.status_code != 200:
            return {
                "statusCode": response.status_code,
                "body": json.dumps({"error": f"API error: {response.text}"})
            }
        forecast_data = response.json()
        logger.info(f"Received {len(forecast_data)} top-level keys")
    except Exception as e:
        return {
            "statusCode": 500,
            "body": json.dumps({"error": f"API request failed: {str(e)}"})
        }
        
    # Upload to S3
    dl_timestamp = datetime.now(UTC)
    download_timestamp_str = dl_timestamp.strftime("%Y%m%dT%H%M%S")

    s3.put_object(
        Bucket=raw_bucket,
        Key=f"uploads/forecast/forecast_{download_timestamp_str}.json",
        Body=json.dumps(forecast_data).encode("utf-8")
    )
    
    logger.info(f"forecast_{download_timestamp_str}.json written to S3")

    # Download time metadata (for download_time_dim)
    download_timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    download_date = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    download_hour = int(datetime.now(timezone.utc).strftime("%H"))
    download_day = int(datetime.now(timezone.utc).strftime("%d"))
    download_month = int(datetime.now(timezone.utc).strftime("%m"))
    download_year = int(datetime.now(timezone.utc).strftime("%Y"))
    download_time_id = hash(download_timestamp) % 1000000

    download_time_data = {
        "download_time_id": download_time_id,
        "timestamp": download_date,
        "hour": download_hour,
        "day": download_day,
        "month": download_month,
        "year": download_year
    }

    # Location metadata (for location_dim)
    location_id = hash(f"{latitude}_{longitude}") % 1000000
    location_data = {
        "location_id": location_id,
        "city": city,
        "country": country,
        "latitude": latitude,
        "longitude": longitude
    }

    # Process forecast data
    forecast_records = []
    for day in forecast_data["days"]:
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

    # Write location_dim and download_time_dim data to S3 raw bucket
    try:
        s3.put_object(
            Bucket=raw_bucket,
            Key=f"forecast_data/location_dim/{location_data['location_id']}.json",
            Body=json.dumps(location_data)
        )
        s3.put_object(
            Bucket=raw_bucket,
            Key=f"forecast_data/download_time_dim/{download_time_data['download_time_id']}.json",
            Body=json.dumps(download_time_data)
        )
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
    except Exception as e:
        return {
            "statusCode": 500,
            "body": json.dumps({"error": f"S3 write failed for forecast data: {str(e)}"})
        }

    return {
        "statusCode": 200,
        "body": json.dumps({"message": f"Successfully ingested {len(forecast_records)} forecast records"})
    }