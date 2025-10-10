resource "aws_sfn_state_machine" "forecast_pipeline" {
  name     = "forecast-pipeline"
  role_arn = aws_iam_role.step_functions_role.arn

  # ✅ CloudWatch logging
  logging_configuration {
    level                  = "ALL" # capture everything
    include_execution_data = true  # store input/output in logs
    log_destination = "${aws_cloudwatch_log_group.step_functions_logs.arn}:*"
  }

  definition = jsonencode({
    Comment = "Sequential DWH Orchestration: Measure → Forecast → ETL → Crawler",
    StartAt = "MeasureIngest",
    States = {
      MeasureIngest = {
        Type     = "Task",
        Resource = "arn:aws:states:::lambda:invoke",
        Parameters = {
          FunctionName = aws_lambda_function.measure_ingest.arn
        },
        Next = "RunApiIngest"
      },

      RunApiIngest = {
        Type     = "Task",
        Resource = "arn:aws:states:::lambda:invoke",
        Parameters = {
          FunctionName = aws_lambda_function.forecast_api_ingest.arn
        },
        Next = "RunETLJob",
        Retry = [
          {
            ErrorEquals     = ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException"],
            IntervalSeconds = 10,
            MaxAttempts     = 3,
            BackoffRate     = 2.0
          }
        ],
        Catch = [
          { ErrorEquals = ["States.ALL"], Next = "FailState" }
        ]
      },

      RunETLJob = {
        Type     = "Task",
        Resource = "arn:aws:states:::glue:startJobRun",
        Parameters = {
          JobName = aws_glue_job.forecast_etl.name
        },
        Next = "RunCrawler",
        Retry = [
          {
            ErrorEquals     = ["Glue.AWSGlueException", "Glue.SdkClientException"],
            IntervalSeconds = 30,
            MaxAttempts     = 2,
            BackoffRate     = 2.0
          }
        ],
        Catch = [
          { ErrorEquals = ["States.ALL"], Next = "FailState" }
        ]
      },

      RunCrawler = {
        Type     = "Task",
        Resource = "arn:aws:states:::aws-sdk:glue:startCrawler",
        Parameters = {
          Name = aws_glue_crawler.forecast_proc_crawler.name
        },
        End = true,
        Retry = [
          {
            ErrorEquals     = ["Glue.AWSGlueException", "Glue.SdkClientException"],
            IntervalSeconds = 30,
            MaxAttempts     = 2,
            BackoffRate     = 2.0
          }
        ],
        Catch = [
          { ErrorEquals = ["States.ALL"], Next = "FailState" }
        ]
      },

      FailState = {
        Type  = "Fail",
        Error = "PipelineFailed",
        Cause = "Pipeline failed — check CloudWatch logs under /aws/states/forecast_pipeline"
      }
    }
  })
}

resource "aws_iam_role" "step_functions_role" {
  name = "step-functions-forecast-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "states.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "step_functions_policy" {
  name = "step-functions-forecast-policy"
  role = aws_iam_role.step_functions_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LambdaInvoke"
        Effect = "Allow"
        Action = ["lambda:InvokeFunction", "lambda:InvokeAsync"]
        Resource = [
          aws_lambda_function.measure_ingest.arn,
          aws_lambda_function.forecast_api_ingest.arn
        ]
      },
      {
        Sid    = "GlueJobAndCrawler"
        Effect = "Allow"
        Action = [
          "glue:StartJobRun",
          "glue:GetJobRun",
          "glue:GetJobRuns",
          "glue:BatchStopJobRun",
          "glue:StartCrawler",
          "glue:GetCrawler",
          "glue:GetCrawlers"
        ]
        Resource = [
          aws_glue_job.forecast_etl.arn,
          aws_glue_crawler.forecast_proc_crawler.arn
        ]
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:PutRetentionPolicy",
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "step_functions_logs_policy" {
  name = "step-functions-logs-policy"
  role = aws_iam_role.step_functions_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutLogEvents",
          "logs:CreateLogStream"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.step_functions_logs.arn}:*"
        ]
      }
    ]
  })
}

# CloudWatch Log Group for Step Functions
resource "aws_cloudwatch_log_group" "step_functions_logs" {
  name              = "/aws/states/forecast_pipeline"
  retention_in_days = 30
}

resource "aws_iam_role" "eventbridge_sfn_role" {
  name = "eventbridge-sfn-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "events.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "eventbridge_sfn_policy" {
  role = aws_iam_role.eventbridge_sfn_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = "states:StartExecution",
        Resource = aws_sfn_state_machine.forecast_pipeline.arn
      }
    ]
  })
}

