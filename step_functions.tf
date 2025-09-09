# step_functions.tf
resource "aws_sfn_state_machine" "weather_pipeline" {
  name     = "weather-pipeline"
  role_arn = aws_iam_role.step_functions_role.arn
  definition = jsonencode({
    Comment = "Weather DWH Pipeline",
    StartAt = "RunCrawler",
    States = {
      RunCrawler = {
        Type = "Task",
        Resource = "arn:aws:states:::aws-sdk:glue:startCrawler",
        Parameters = {
          Name = aws_glue_crawler.weather_raw_crawler.name
        },
        Next = "RunETLJob"
      },
      RunETLJob = {
        Type = "Task",
        Resource = "arn:aws:states:::glue:startJobRun",
        Parameters = {
          JobName = aws_glue_job.weather_etl.name
        },
        End = true
      }
    }
  })
}

resource "aws_iam_role" "step_functions_role" {
  name = "weather_step_functions_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "states.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "step_functions_policy" {
  role = aws_iam_role.step_functions_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["glue:StartCrawler", "glue:StartJobRun"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      }
    ]
  })
}