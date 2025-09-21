# ~/dwh_iac/glue.tf: 1. clean NULLS [S3 raw->S3 proc] 2.crawler creates glue catalog [S3 proc->ecofarm_gluedb]

# upload forecast_etl.py to S3
resource "aws_s3_object" "glue_script" {
  bucket = aws_s3_bucket.forecast_raw.bucket
  key    = "scripts/forecast_etl.py"
  source = "~/dwh_iac/forecast_etl.py"
  etag   = filemd5("~/dwh_iac/forecast_etl.py") # only oploads file if the local file has diff checksum than existing one
}

resource "aws_glue_job" "forecast_etl" {
  name     = "forecast-etl-job"
  role_arn = aws_iam_role.glue_role.arn
  description = "run forecast_etl.py to clean NULLs"
  number_of_workers = 1 #optional, default: 5
  command {
    script_location = "s3://${aws_s3_bucket.forecast_raw.bucket}/scripts/forecast_etl.py"
    python_version  = "3"
  }
  default_arguments = {
    "--job-language" = "python"
  }
  max_capacity = 1.0 # Free Tier eligible [https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_job#max_capacity-2]
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
  description   = "Crawls S3 forecast processed data"

  s3_target {
    path = "s3://forecast-processed-data-${random_string.suffix.result}/"
  }

  schedule = "cron(0 0 * * ? *)" # Run daily at midnight UTC
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

