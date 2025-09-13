# /iac/s3.tf

resource "aws_s3_bucket" "forecast_raw" {
  bucket = "forecast-raw-data-${random_string.suffix.result}"
  tags = {
    Name = "forecast Raw Data"
  }
}

resource "aws_s3_bucket" "forecast_processed" {
  bucket = "forecast-processed-data-${random_string.suffix.result}"
  tags = {
    Name = "forecast Processed Data"
  }
}
