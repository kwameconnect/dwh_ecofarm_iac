# /iac/lambda.tf
resource "aws_lambda_function" "forecast_ingest" {
  function_name    = "forecast-api-ingest"
  handler          = "index.handler"
  runtime          = "python3.9"
  role             = aws_iam_role.lambda_role.arn
  filename         = "lambda_function.zip"
  source_code_hash = filebase64sha256("lambda_function.zip")
  timeout          = 30
  environment {
    variables = {
      VISUALCROSSING_API_KEY = var.visualcrossing_api_key
      S3_RAW_BUCKET          = aws_s3_bucket.forecast_raw.bucket
    }
  }
  # /iac/lambda.tf (add to aws_lambda_function.forecast_ingest)
  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.redshift_sg.id]
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
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      }
    ]
  })
}
