# /iac/main.tf
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "ecofarm-dwh-vpc"
  }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id                             # Correct reference
  cidr_block        = ["10.0.2.0/24", "10.0.3.0/24"][count.index] # Use non-conflicting CIDR blocks
  availability_zone = ["eu-north-1a", "eu-north-1b"][count.index]
  tags = {
    Name = "ecofarm-dwh-private-subnet-${count.index}"
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Fetch the latest Amazon Linux 2 AMI (free-tier eligible)
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# -------------------------------
# EC2 Instance (Free-Tier Eligible)
# -------------------------------
resource "aws_instance" "free_tier" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.dwh_sg.id]
  subnet_id              = aws_subnet.private[0].id

  tags = {
    Name = "free-tier-ec2"
  }
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# -------------------------------
# AWS Budget ($1 cap with alert)
# -------------------------------
resource "aws_budgets_budget" "monthly" {
  name         = "monthly-cost"
  budget_type  = "COST"
  limit_amount = "1"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 1
    threshold_type             = "ABSOLUTE_VALUE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_email]
  }
}

# ----------------------------------
# AWS S3 Serverless Storage Service
# ----------------------------------
resource "aws_s3_bucket" "forecast_raw" {
  bucket = "forecast-raw-data-${random_string.suffix.result}"
  tags = {
    Name = "forecast Raw Data"
  }
}

resource "aws_s3_bucket" "forecast_processed" {
  bucket = "forecast-processed-data-${random_string.suffix.result}"
  tags = {
    Name = "forecast Processed Data"
  }
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = "ecofarm-dwh-terraform-state"
  tags = {
    Name = "ecofarm-dwh-terraform-state"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# terraform {
#  backend "s3" {
#    bucket = "ecofarm-dwh-terraform-state"
#    key    = "state/terraform.tfstate"
#    region = "eu-north-1"
#  }
# }