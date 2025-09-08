# /iac/lambda.tf
resource "aws_lambda_function" "weather_ingestion" {
  function_name = "weather-api-ingestion"
  handler       = "index.handler"
  runtime       = "python3.9"
  role          = aws_iam_role.lambda_role.arn
  filename      = "lambda_function.zip"
  source_code_hash = filebase64sha256("lambda_function.zip")
  timeout       = 30
  environment {
    variables = {
      VISUAL_CROSSING_API_KEY = "${var.visualcrossing_api_key}"  # Replace with actual key
      S3_RAW_BUCKET           = aws_s3_bucket.weather_raw.bucket
    }
  }
}

resource "aws_iam_role" "lambda_role" {
  name = "weather_lambda_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
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
          "${aws_s3_bucket.weather_raw.arn}/*",
          "${aws_s3_bucket.weather_processed.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      }
    ]
  })
}
