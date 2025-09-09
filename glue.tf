# weather_etl.py
import boto3
import pandas as pd

s3_client = boto3.client("s3")
redshift_client = boto3.client("redshift-data")

def transform_forecast():
    obj = s3_client.get_object(Bucket="weather-raw-data-<suffix>", Key="forecast/*")
    df = pd.read_json(obj["Body"])
    df = df.dropna() # Clean nulls
    # Save transformed data to S3
    s3_client.put_object(
        Bucket="weather-processed-data-<suffix>",
        Key="forecast/transformed/data.csv",
        Body=df.to_csv(index=False)
    )
    # Load to Redshift
    redshift_client.execute_statement(
        Database="weather_db",
        WorkgroupName="weather-dwh-workgroup",
        Sql=f"COPY forecast_data_fact FROM 's3://weather-processed-data-<suffix>/forecast/transformed/' IAM_ROLE 'arn:aws:iam::...:role/weather_glue_role' CSV;"
    )

def transform_energy():
    # Similar logic for energy data
    pass

def transform_water():
    # Similar logic for water data
    pass