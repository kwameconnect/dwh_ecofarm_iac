# /dwh_iac/cloudwatch_scheduler.tf
resource "aws_cloudwatch_event_rule" "daily_pipeline_trigger" {
  name                = "forecast-pipeline-daily"
  description         = "Triggers Step Functions pipeline daily at 11:50 PM UTC"
  schedule_expression = "cron(50 23 * * ? *)"
}

resource "aws_cloudwatch_event_target" "step_functions_target" {
  rule      = aws_cloudwatch_event_rule.daily_pipeline_trigger.name
  target_id = "forecast-pipeline"
  arn       = aws_sfn_state_machine.forecast_pipeline.arn
}

resource "aws_lambda_permission" "allow_step_functions" {
  statement_id  = "AllowExecutionFromStepFunctions"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.forecast_api_ingest.function_name
  principal     = "states.amazonaws.com"
}

# Allow CloudWatch Events to start the Step Function
resource "aws_iam_role_policy" "allow_events_to_start_step_function" {
  role = aws_iam_role.step_functions_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["states:StartExecution"]
        Resource = aws_sfn_state_machine.forecast_pipeline.arn
      }
    ]
  })
}
