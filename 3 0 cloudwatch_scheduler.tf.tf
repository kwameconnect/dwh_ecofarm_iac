# /dwh_iac/cloudwatch_scheduler.tf
resource "aws_cloudwatch_event_rule" "daily_pipeline_trigger" {
  name                = "forecast-pipeline-daily"
  description         = "Triggers Step Functions pipeline daily at 10:00 PM UTC"
  schedule_expression = "cron(00 22 * * ? *)"
}

resource "aws_cloudwatch_event_target" "step_functions_target" {
  rule      = aws_cloudwatch_event_rule.daily_pipeline_trigger.name
  target_id = "forecast-pipeline"
  arn       = aws_sfn_state_machine.forecast_pipeline.arn
  role_arn  = aws_iam_role.eventbridge_sfn_role.arn
  input = jsonencode({
    action = "MeasureIngest"
  })

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
