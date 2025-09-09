# main.tf
provider "aws" {
  region = "eu-north-1" # Free Tier-eligible region
}

# Random string for unique resource names
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}