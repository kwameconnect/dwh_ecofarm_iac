# glue.tf
resource "aws_glue_catalog_database" "ecofarm_db" {
  name = "ecofarm_db"
}

resource "aws_glue_crawler" "forecast_raw_crawler" {
  database_name = aws_glue_catalog_database.ecofarm_db.name
  name          = "forecast-raw-crawler"
  role          = aws_iam_role.glue_role.arn
  s3_target {
    path = "s3://${aws_s3_bucket.forecast_raw.bucket}/"
  }
}

resource "aws_glue_job" "forecast_etl" {
  name     = "forecast-etl-job"
  role_arn = aws_iam_role.glue_role.arn
  command {
    script_location = "s3://${aws_s3_bucket.forecast_processed.bucket}/scripts/forecast_etl.py"
    python_version  = "3"
  }
  default_arguments = {
    "--job-language" = "python"
  }
  max_capacity = 0.0625 # Minimum for Python shell, Free Tier eligible
}

resource "aws_iam_role" "glue_role" {
  name = "forecast_glue_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "glue_policy" {
  role = aws_iam_role.glue_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject"]
        Resource = [
          "${aws_s3_bucket.forecast_raw.arn}/*",
          "${aws_s3_bucket.forecast_processed.arn}/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["redshift-data:ExecuteStatement", "redshift:GetClusterCredentials"]
        Resource = "*"
      }
    ]
  })
}
