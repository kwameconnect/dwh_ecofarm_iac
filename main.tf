# main.tf
# Random string for unique resource names
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

provider "aws" {
  region = var.region
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "ecofarm-dwh-vpc"
  }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index}.0/24"
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
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
  ami           = data.aws_ami.amazon_linux.id   # 👈 dynamically fetched
  instance_type = var.instance_type

  tags = {
    Name = "free-tier-ec2"
  }
}

resource "random_id" "suffix" {
  byte_length = 4
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