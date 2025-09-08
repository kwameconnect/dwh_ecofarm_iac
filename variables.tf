# /iac/variables.tf
variable "redshift_db_name" {
    description = "Redshift database name"
    type = string
    default = "weather_db"
}

variable "redshift_admin_username" {
    description = "Admin username for Redshift"
    type = string 
    default = "admin"
}

variable "redshift_admin_password" {
    description = "Admin password for Redshift" 
    type = string
    sensitive = true
}

variable "visual_crossing_api_key" {
    description = "Visual Crossing API key"
    type = string
    sensitive = true
}

