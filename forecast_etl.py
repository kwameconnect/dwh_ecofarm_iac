# ~/dwh_iac/forecast_etl.py: cleans the raw bucket data from nulls into processed bucket
import boto3
import pandas as pd

s3_client = boto3.client("s3")
#redshift_client = boto3.client("redshift-data")

def transform_forecast():
    obj = s3_client.get_object(Bucket="forecast-raw-data-<suffix>", Key="forecast/*")
    df = pd.read_json(obj["Body"])
    df = df.dropna() # Clean nulls
    # Save transformed data to S3
    s3_client.put_object(
        Bucket="forecast-processed-data-<suffix>",
        Key="forecast/data.csv",
        Body=df.to_csv(index=False)
    )

def transform_energy():
    # Similar logic for energy data
    pass

def transform_water():
    # Similar logic for water data
    pass