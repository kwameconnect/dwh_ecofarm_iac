# ~/dwh_iac/glue.tf: 1. clean NULLS [S3 raw->S3 proc] 2.crawler creates glue catalog [S3 proc->ecofarm_gluedb]

# upload forecast_etl.py to S3
resource "aws_s3_object" "glue_script" {
  bucket = aws_s3_bucket.forecast_raw.bucket
  key    = "scripts/forecast_etl.py"
  source = "~/dwh_iac/forecast_etl.py"
  etag   = filemd5("~/dwh_iac/forecast_etl.py") # only oploads file if the local file has diff checksum than existing one
}

resource "aws_glue_job" "forecast_etl" {
  name        = "forecast-etl-job"
  role_arn    = aws_iam_role.glue_role.arn
  description = "run forecast_etl.py to clean NULLs"
  command {
    script_location = "s3://${aws_s3_bucket.forecast_raw.bucket}/scripts/forecast_etl.py"
    python_version  = "3"
  }
  default_arguments = {
    "--job-language" = "python"
    "--RAW_BUCKET"   = aws_s3_bucket.forecast_raw.bucket
    "--PROC_BUCKET"  = aws_s3_bucket.forecast_processed.bucket
  }
  worker_type       = "G.1X"
  number_of_workers = 10
}

# Glue database for the DWH
resource "aws_glue_catalog_database" "ecofarm_gluedb" {
  name        = "ecofarm-gluedb"
  description = "Glue database for Ecofarm DWH"
}

# Glue crawler to catalog S3 data
resource "aws_glue_crawler" "forecast_proc_crawler" {
  database_name = aws_glue_catalog_database.ecofarm_gluedb.name
  name          = "forecast-proc-crawler"
  role          = aws_iam_role.glue_role.arn
  description   = "Crawls processed forecast data on S3"

  s3_target {
    path = "s3://forecast-processed-data-${random_string.suffix.result}/forecast_data/location_dim"
  }

  s3_target {
    path = "s3://forecast-processed-data-${random_string.suffix.result}/forecast_data/forecast_fact"
  }

  s3_target {
    path = "s3://forecast-processed-data-${random_string.suffix.result}/forecast_data/download_time_dim"
  }

  s3_target {
    path = "s3://forecast-processed-data-${random_string.suffix.result}/forecast_data/forecast_time_dim"
  }
}

#glue tables
resource "aws_glue_catalog_table" "forecast_time_dim" {
  name          = "forecast_time_dim"
  database_name = aws_glue_catalog_database.ecofarm_gluedb.name
  table_type    = "EXTERNAL_TABLE"

  storage_descriptor {
    location      = "s3://forecast-processed-data-${random_string.suffix.result}/forecast_data/forecast_time_dim"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "json"
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
    }

    columns {
      name = "forecast_time_id"
      type = "bigint"
    }

    columns {
      name = "date"
      type = "date"
    }

    columns {
      name = "hour"
      type = "int"
    }

    columns {
      name = "day"
      type = "int"
    }

    columns {
      name = "month"
      type = "int"
    }

    columns {
      name = "year"
      type = "int"
    }
  }

  parameters = {
    "classification" = "json"
  }
}

resource "aws_glue_catalog_table" "location_dim" {
  name          = "location_dim"
  database_name = aws_glue_catalog_database.ecofarm_gluedb.name
  table_type    = "EXTERNAL_TABLE"

  storage_descriptor {
    location      = "s3://forecast-processed-data-${random_string.suffix.result}/forecast_data/location_dim"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "json"
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
    }

    columns {
      name = "location_id"
      type = "bigint"
    }

    columns {
      name = "city"
      type = "string"
    }

    columns {
      name = "country"
      type = "string"
    }

    columns {
      name = "latitude"
      type = "double"
    }

    columns {
      name = "longitude"
      type = "double"
    }
  }

  parameters = {
    "classification" = "json"
  }
}

resource "aws_glue_catalog_table" "download_time_dim" {
  name          = "download_time_dim"
  database_name = aws_glue_catalog_database.ecofarm_gluedb.name
  table_type    = "EXTERNAL_TABLE"

  storage_descriptor {
    location      = "s3://forecast-processed-data-${random_string.suffix.result}/forecast_data/download_time_dim"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "json"
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
    }

    columns {
      name = "download_time_id"
      type = "bigint"
    }

    columns {
      name = "timestamp"
      type = "string" # could also be 'timestamp' if you write ISO timestamps
    }

    columns {
      name = "hour"
      type = "int"
    }

    columns {
      name = "day"
      type = "int"
    }

    columns {
      name = "month"
      type = "int"
    }

    columns {
      name = "year"
      type = "int"
    }
  }

  parameters = {
    "classification" = "json"
  }
}

resource "aws_glue_catalog_table" "forecast_fact" {
  name          = "forecast_fact"
  database_name = aws_glue_catalog_database.ecofarm_gluedb.name
  table_type    = "EXTERNAL_TABLE"

  storage_descriptor {
    location      = "s3://forecast-processed-data-${random_string.suffix.result}/forecast_data/forecast_fact"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "json"
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
    }

    columns {
      name = "forecast_id"
      type = "string"
    }

    columns {
      name = "location_id"
      type = "bigint"
    }

    columns {
      name = "time_id"
      type = "bigint"
    }

    columns {
      name = "temperature_c"
      type = "double"
    }

    columns {
      name = "rain_mm"
      type = "double"
    }

    columns {
      name = "solarradiation_w"
      type = "double"
    }

    columns {
      name = "cloudcover"
      type = "int"
    }

    columns {
      name = "wind_speed_kmh"
      type = "double"
    }

    columns {
      name = "humidity"
      type = "double"
    }

    columns {
      name = "weather_condition"
      type = "string"
    }
  }

  parameters = {
    "classification" = "json"
  }
}

resource "aws_glue_catalog_table" "solar_energy_time_dim" {
  name          = "solar_energy_time_dim"
  database_name = aws_glue_catalog_database.ecofarm_gluedb.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    classification = "json"
  }

  storage_descriptor {
    location      = "s3://forecast-processed-data-${random_string.suffix.result}/forecast_data/solar_time_dim/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.IgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "json"
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
    }

    columns {
      name = "solar_energy_time_id"
      type = "bigint"
    }
    columns {
      name = "date"
      type = "date"
    }
    columns {
      name = "hour"
      type = "int"
    }
    columns {
      name = "day"
      type = "int"
    }
    columns {
      name = "month"
      type = "int"
    }
    columns {
      name = "year"
      type = "int"
    }
  }
}

resource "aws_glue_catalog_table" "solar_energy_fact" {
  name          = "solar_energy_fact"
  database_name = aws_glue_catalog_database.ecofarm_gluedb.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    classification = "json"
  }

  storage_descriptor {
    location      = "s3://forecast-processed-data-${random_string.suffix.result}/forecast_data/solar_energy_fact/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.IgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "json"
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
    }

    columns {
      name = "energy_id"
      type = "bigint"
    }
    columns {
      name    = "location_id"
      type    = "bigint"
      comment = "FK to locations_dim.location_id"
    }
    columns {
      name    = "energy_time_id"
      type    = "bigint"
      comment = "FK to solar_energy_time_dim.solar_energy_time_id"
    }
    columns {
      name = "solarenergy_kwh"
      type = "decimal(10,2)"
    }
    columns {
      name = "date_uploaded"
      type = "date"
    }
  }
}

resource "aws_glue_catalog_table" "water_level_time_dim" {
  name          = "water_level_time_dim"
  database_name = aws_glue_catalog_database.ecofarm_gluedb.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    classification = "json"
  }

  storage_descriptor {
    location      = "s3://forecast-processed-data-${random_string.suffix.result}/forecast_data/water_level_time_dim/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.IgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "json"
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
    }

    columns {
      name = "water_level_time_id"
      type = "bigint"
    }
    columns {
      name = "date"
      type = "date"
    }
    columns {
      name = "hour"
      type = "int"
    }
    columns {
      name = "day"
      type = "int"
    }
    columns {
      name = "month"
      type = "int"
    }
    columns {
      name = "year"
      type = "int"
    }
  }
}

resource "aws_glue_catalog_table" "water_level_fact" {
  name          = "water_level_fact"
  database_name = aws_glue_catalog_database.ecofarm_gluedb.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    classification = "json"
  }

  storage_descriptor {
    location      = "s3://forecast-processed-data-${random_string.suffix.result}/forecast_data/water_level_fact/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.IgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "json"
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
    }

    columns {
      name = "water_level_id"
      type = "bigint"
    }
    columns {
      name    = "location_id"
      type    = "bigint"
      comment = "FK to locations_dim.location_id"
    }
    columns {
      name    = "level_time_id"
      type    = "bigint"
      comment = "FK to water_level_time_dim.water_level_time_id"
    }
    columns {
      name = "water_level_mm"
      type = "bigint"
    }
    columns {
      name = "rain_collected_mm"
      type = "bigint"
    }
    columns {
      name = "date_uploaded"
      type = "date"
    }
  }
}


# IAM role for Glue
resource "aws_iam_role" "glue_role" {
  name = "ecofarm-glue-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "glue_policy" {
  role = aws_iam_role.glue_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::forecast-raw-data-${random_string.suffix.result}",
          "arn:aws:s3:::forecast-raw-data-${random_string.suffix.result}/*",
          "arn:aws:s3:::forecast-processed-data-${random_string.suffix.result}",
          "arn:aws:s3:::forecast-processed-data-${random_string.suffix.result}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "glue:*",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_security_group" "dwh_sg" {
  vpc_id      = aws_vpc.main.id
  name        = "ecofarm-dwh-sg"
  description = "Security group for Lambda access"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] # Restrict in production
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ecofarm-dwh-sg"
  }
}

# Athena workgroup
resource "aws_athena_workgroup" "ecofarm_dwh" {
  name = "ecofarm-dwh-workgroup"
  configuration {
    result_configuration {
      output_location = "s3://forecast-processed-data-${random_string.suffix.result}/athena-results/"
    }
  }
}

