data "aws_s3_bucket" "RAW_BUCKET" {
  bucket = aws_s3_bucket.forecast_raw.bucket
}

resource "aws_lambda_function" "json_ingest" {
  function_name = "json_ingest"
  role          = aws_iam_role.json_ingest_lambda_role.arn
  handler       = "json_ingest.lambda_handler"
  runtime       = "python3.12"
  timeout       = 600

  filename         = "${path.module}/json_ingest.zip"
  source_code_hash = filebase64sha256("${path.module}/json_ingest.zip")
  layers = [

  ]

  environment {
    variables = {
      S3_RAW_BUCKET = aws_s3_bucket.forecast_raw.bucket
      latitude      = var.latitude
      longitude     = var.longitude
      LOG_LEVEL     = "INFO"
    }
  }
}

resource "aws_s3_object" "uploads_folder" {
  bucket = data.aws_s3_bucket.RAW_BUCKET.id
  key    = "uploads/"
}

resource "aws_s3_object" "measured_folder" {
  bucket = data.aws_s3_bucket.RAW_BUCKET.id
  key    = "uploads/measured/"
}

resource "aws_s3_object" "hist_folder" {
  bucket = data.aws_s3_bucket.RAW_BUCKET.id
  key    = "uploads/hist/"
}

# --- IAM Role for Lambda ---
resource "aws_iam_role" "json_ingest_lambda_role" {
  name = "json_ingest_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# --- IAM Policy: Allow Lambda to access S3 and write logs ---
resource "aws_iam_policy" "json_ingest_lambda_policy" {
  name        = "json_ingest_lambda_policy"
  description = "Allow json_ingest Lambda to access S3 and write logs"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ],
        Resource = [
          "arn:aws:s3:::forecast-raw-data-${random_string.suffix.result}/*",
          "arn:aws:s3:::forecast-processed-data-${random_string.suffix.result}/*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "s3:ListBucket"
        ],
        Resource = [
          "arn:aws:s3:::forecast-raw-data-${random_string.suffix.result}",
          "arn:aws:s3:::forecast-processed-data-${random_string.suffix.result}"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "cloudwatch:PutMetricData"
        ],
        Resource = "*"
      }
    ]
  })
}

# --- Attach the policy to the role ---
resource "aws_iam_role_policy_attachment" "json_ingest_attach" {
  role       = aws_iam_role.json_ingest_lambda_role.name
  policy_arn = aws_iam_policy.json_ingest_lambda_policy.arn
}

# --- Output for referencing in Step Function ---
output "json_ingest_lambda_arn" {
  value = aws_lambda_function.json_ingest.arn
}
