# /iac/eventbridge.tf
# EventBridge rule to trigger Lambda daily at 11:50 PM UTC
resource "aws_cloudwatch_event_rule" "daily_lambda_trigger" {
  name                = "forecast-api-ingest-daily"
  description         = "Triggers forecast-api-ingest Lambda daily at 11:50 PM UTC"
  schedule_expression = "cron(50 23 * * ? *)" # Runs at 11:50 PM UTC daily
}

# EventBridge target to invoke the Lambda function
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.daily_lambda_trigger.name
  target_id = "forecast-api-ingest"
  arn       = aws_lambda_function.forecast_ingest.arn
}

# IAM policy to allow EventBridge to invoke Lambda
resource "aws_iam_policy" "eventbridge_invoke_lambda" {
  name        = "EventBridgeInvokeForecastLambda"
  description = "Allows EventBridge to invoke forecast-api-ingest Lambda"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = aws_lambda_function.forecast_ingest.arn
      }
    ]
  })
}

# Attach the policy to the Lambda execution role
resource "aws_iam_role_policy_attachment" "eventbridge_lambda_policy" {
  role       = aws_iam_role.lambda_role.name # References forecast_lambda_role from lambda.tf
  policy_arn = aws_iam_policy.eventbridge_invoke_lambda.arn
}

# Add permission for EventBridge to invoke Lambda
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.forecast_ingest.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_lambda_trigger.arn
}
