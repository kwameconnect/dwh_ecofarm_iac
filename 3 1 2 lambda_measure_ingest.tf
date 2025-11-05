# --- Lambda Function Definition ---
resource "aws_lambda_function" "measure_ingest" {
  function_name = "measure_ingest"
  role          = aws_iam_role.measure_ingest_lambda_role.arn
  handler       = "measure_ingest.lambda_handler"
  runtime       = "python3.12"
  timeout       = 900

  filename         = "${path.module}/measure_ingest.zip"
  source_code_hash = filebase64sha256("${path.module}/measure_ingest.zip")
  layers = [
    "arn:aws:lambda:eu-north-1:770693421928:layer:Klayers-p312-pandas:17"
  ]

  environment {
    variables = {
      RAW_BUCKET = aws_s3_bucket.forecast_raw.bucket
      LOG_LEVEL  = "INFO"
    }
  }
}

# --- IAM Role for Lambda ---
resource "aws_iam_role" "measure_ingest_lambda_role" {
  name = "measure_ingest_lambda_role"

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
resource "aws_iam_policy" "measure_ingest_lambda_policy" {
  name        = "measure_ingest_lambda_policy"
  description = "Allow measure_ingest Lambda to access S3 and write logs"

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
resource "aws_iam_role_policy_attachment" "measure_ingest_attach" {
  role       = aws_iam_role.measure_ingest_lambda_role.name
  policy_arn = aws_iam_policy.measure_ingest_lambda_policy.arn
}

# --- Optional: Lambda permission to be invoked by Step Functions ---
resource "aws_lambda_permission" "allow_step_functions" {
  statement_id  = "AllowStepFunctionsInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.measure_ingest.function_name
  principal     = "states.amazonaws.com"
}

# --- Output for referencing in Step Function ---
output "measure_ingest_lambda_arn" {
  value = aws_lambda_function.measure_ingest.arn
}
