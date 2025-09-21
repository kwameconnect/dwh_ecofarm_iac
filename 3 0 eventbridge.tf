# /dwh_iac/eventbridge.tf: invokes lambda function forecast-api-ingest->index.py->api to s3 raw
resource "aws_cloudwatch_event_rule" "daily_lambda_trigger" {
  name                = "forecast-api-ingest-daily"
  description         = "Triggers forecast-api-ingest Lambda daily at 11:50 PM UTC"
  schedule_expression = "cron(50 23 * * ? *)"
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.daily_lambda_trigger.name
  target_id = "forecast-api-ingest"
  arn       = aws_lambda_function.forecast_api_ingest.arn
}

resource "aws_iam_policy" "eventbridge_invoke_lambda" {
  name        = "EventBridgeInvokeForecastLambda"
  description = "Allows EventBridge to invoke forecast-api-ingest Lambda"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction"]
      Resource = aws_lambda_function.forecast_api_ingest.arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eventbridge_lambda_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.eventbridge_invoke_lambda.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.forecast_api_ingest.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_lambda_trigger.arn
}