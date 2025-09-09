# /iac/s3.tf

# Generate a random suffix to ensure bucket name uniqueness
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_s3_bucket" "weather_raw" {
  bucket = "weather-raw-data-${random_string.suffix.result}"
  tags = {
    Name = "Weather Raw Data"
  }
}

resource "aws_s3_bucket" "weather_processed" {
  bucket = "weather-processed-data-${random_string.suffix.result}"
  tags = {
    Name = "Weather Processed Data"
  }
}
