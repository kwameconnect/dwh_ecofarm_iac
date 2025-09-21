# /dwh_iac/step_functions.tf
resource "aws_sfn_state_machine" "forecast_pipeline" {
  name     = "forecast-pipeline"
  role_arn = aws_iam_role.step_functions_role.arn

  # Enable logging into CloudWatch Logs
  logging_configuration {
    level                  = "ALL"  # Options: OFF, ERROR, ALL
    include_execution_data = true
    destinations = [
      {
        cloudwatch_logs_log_group = {
          log_group_arn = aws_cloudwatch_log_group.step_functions_logs.arn
        }
      }
    ]
  }

  definition = jsonencode({
    Comment = "Weather Forecast DWH Pipeline with error handling",
    StartAt = "RunApiIngest",
    States = {
      RunApiIngest = {
        Type     = "Task",
        Resource = "arn:aws:states:::lambda:invoke",
        Parameters = {
          FunctionName = aws_lambda_function.forecast_api_ingest.arn
        },
        Next = "RunETLJob",
        Retry = [
          {
            ErrorEquals     = ["Lambda.ServiceException","Lambda.AWSLambdaException","Lambda.SdkClientException"],
            IntervalSeconds = 10,
            MaxAttempts     = 3,
            BackoffRate     = 2.0
          }
        ],
        Catch = [
          {
            ErrorEquals = ["States.ALL"],
            Next        = "FailState"
          }
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
            ErrorEquals     = ["Glue.AWSGlueException","Glue.SdkClientException"],
            IntervalSeconds = 30,
            MaxAttempts     = 2,
            BackoffRate     = 2.0
          }
        ],
        Catch = [
          {
            ErrorEquals = ["States.ALL"],
            Next        = "FailState"
          }
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
            ErrorEquals     = ["Glue.AWSGlueException","Glue.SdkClientException"],
            IntervalSeconds = 30,
            MaxAttempts     = 2,
            BackoffRate     = 2.0
          }
        ],
        Catch = [
          {
            ErrorEquals = ["States.ALL"],
            Next        = "FailState"
          }
        ]
      },
      FailState = {
        Type  = "Fail",
        Error = "PipelineFailed",
        Cause = "Pipeline execution failed at some step. errors are pushed into '/aws/states/forecast_pipeline' in CloudWatch"
      }
    }
  })
}

# Step Functions IAM Role
resource "aws_iam_role" "step_functions_role" {
  name = "forecast_step_functions_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "states.amazonaws.com" }
    }]
  })
}

# Permissions for Step Functions
resource "aws_iam_role_policy" "step_functions_policy" {
  role = aws_iam_role.step_functions_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["glue:StartCrawler", "glue:StartJobRun"],
        Resource = "*"
      },
      {
        Effect   = "Allow",
        Action   = ["lambda:InvokeFunction"],
        Resource = aws_lambda_function.forecast_api_ingest.arn
      },
      {
        Effect   = "Allow",
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}

# CloudWatch Log Group for Step Functions
resource "aws_cloudwatch_log_group" "step_functions_logs" {
  name              = "/aws/states/forecast_pipeline"
  retention_in_days = 30
}
