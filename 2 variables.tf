# /iac/variables.tf
variable "visualcrossing_api_key" {
  description = "Visualcrossing API key"
  type        = string
  sensitive   = true
}

variable "latitude" {
  description = "Ecofarm latitude"
  type        = number
  sensitive   = true
}

variable "longitude" {
  description = "Ecofarm longitude"
  type        = number
  sensitive   = true
}

variable "instance_type" {
  description = "EC2 instance type (restricted to free tier eligible)"
  type        = string
  default     = "t3.micro"

  validation {
    condition     = contains(["t4g.micro", "t3.micro"], var.instance_type)
    error_message = "Only t4g.micro and t3.micro are allowed (free-tier eligible)."
  }
}

variable "budget_email" {
  description = "Email for budget alerts"
  type        = string
}

variable "region" {
  description = "Region of AWS infrastructure"
  type        = string
  default     = "eu-north-1"
}
