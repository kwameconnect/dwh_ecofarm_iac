# /iac/lambda.tf invokes api_ingest.zip -> API_ingest.py: api response -> S3 forecast_raw bucket as facts&dimensions .json
resource "aws_lambda_function" "forecast_api_ingest" {
  function_name    = "forecast-api-ingest"
  handler          = "api_ingest.lambda_handler"
  runtime          = "python3.12"
  role             = aws_iam_role.lambda_role.arn
  filename         = "api_ingest.zip"
  source_code_hash = filebase64sha256("api_ingest.zip")
  timeout          = 30
  layers = [
    "arn:aws:lambda:eu-north-1:770693421928:layer:Klayers-p312-requests:17"
  ]
  environment {
    variables = {
      VISUALCROSSING_API_KEY = var.visualcrossing_api_key
      latitude               = var.latitude
      longitude              = var.longitude
      S3_RAW_BUCKET          = aws_s3_bucket.forecast_raw.bucket
    }
  }
}

resource "aws_iam_role" "lambda_role" {
  name = "lambda_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:GetObject"]
        Resource = [
          "${aws_s3_bucket.forecast_raw.arn}/*",
          "${aws_s3_bucket.forecast_processed.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
        ]
        Resource = "*"
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