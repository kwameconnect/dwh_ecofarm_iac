# /iac/lambda_code/index.py: downloads api response to S3 raw_bucket as facts and dimensions in json files 
import requests
import boto3
import json
import os
from datetime import datetime, timezone

def handler(event, context):
    # Configuration from environment variables
    api_key = os.getenv("VISUALCROSSING_API_KEY")
    raw_bucket = os.getenv("S3_RAW_BUCKET")
    latitude = 5.574
    longitude = -0.565
    city = "Samsamso Ecofarm"
    country = "Ghana"
    url = f"https://weather.visualcrossing.com/VisualCrossingWebServices/rest/services/timeline/{latitude}%2C{longitude}/tomorrow?unitGroup=metric&include=days%2Chours&key={api_key}&contentType=json"

    # Make API request
    try:
        response = requests.get(url, timeout=10)
        if response.status_code != 200:
            return {
                "statusCode": response.status_code,
                "body": json.dumps({"error": f"API error: {response.text}"})
            }
        forecast_data = response.json()
    except Exception as e:
        return {
            "statusCode": 500,
            "body": json.dumps({"error": f"API request failed: {str(e)}"})
        }

    # Initialize S3 client
    s3 = boto3.client("s3")

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

    # Location data (for location_dim)
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
                "date": forecast_date,
                "hour": hour,
                "day": forecast_day,
                "month": forecast_month,
                "year": forecast_year
            }

            # Forecast fact data (for forecast_data_fact)
            forecast_record = {
                "forecast_id": f"{location_id}_{forecast_time_id}_{context.aws_request_id}",
                "location_id": location_id,
                "time_id": download_time_id,
                "temperature_c": float(hour_data["temp"]),
                "rain_mm": float(hour_data["precip"]),
                "solarradiation_w": float(hour_data["solarradiation"]),
                "cloudcover": int(hour_data["cloudcover"]),
                "wind_speed_kmh": float(hour_data["windspeed"]),
                "humidity": float(hour_data["humidity"]),
                "weather_condition": hour_data["conditions"]
            }
            forecast_records.append(forecast_record)

            # Write forecast_time data to S3 raw bucket
            try:
                s3.put_object(
                    Bucket=raw_bucket,
                    Key=f"forecast_time/{forecast_time_data['forecast_time_id']}.json",
                    Body=json.dumps(forecast_time_data)
                )
            except Exception as e:
                return {
                    "statusCode": 500,
                    "body": json.dumps({"error": f"S3 write failed for forecast_time: {str(e)}"})
                }

    # Write location and download_time data to S3 raw bucket
    try:
        s3.put_object(
            Bucket=raw_bucket,
            Key=f"location/{location_data['location_id']}.json",
            Body=json.dumps(location_data)
        )
        s3.put_object(
            Bucket=raw_bucket,
            Key=f"download_time/{download_time_data['download_time_id']}.json",
            Body=json.dumps(download_time_data)
        )
    except Exception as e:
        return {
            "statusCode": 500,
            "body": json.dumps({"error": f"S3 write failed for dimension data: {str(e)}"})
        }

    # Write forecast data to S3 raw bucket
    try:
        for record in forecast_records:
            s3.put_object(
                Bucket=raw_bucket,
                Key=f"forecast/{record['forecast_id']}.json",
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