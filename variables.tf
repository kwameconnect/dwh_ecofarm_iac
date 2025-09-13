# /iac/variables.tf
variable "redshift_db_name" {
  description = "Redshift database name"
  type        = string
  default     = "ecofarm_db"
}

variable "redshift_admin_username" {
  description = "Admin username for Redshift"
  type        = string
  default     = "admin"
}

variable "redshift_admin_password" {
  description = "Admin password for Redshift"
  type        = string
  sensitive   = true
}

variable "visualcrossing_api_key" {
  description = "Visualcrossing API key"
  type        = string
  sensitive   = true
}

variable "instance_type" {
  description = "EC2 instance type (restricted to free tier eligible)"
  type        = string
  default     = "t2.micro"

  validation {
    condition     = contains(["t2.micro", "t3.micro"], var.instance_type)
    error_message = "Only t2.micro and t3.micro are allowed (free-tier eligible)."
  }
}

variable "budget_email" {
  description = "Email for budget alerts"
  type        = string
}