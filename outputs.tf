output "ec2_instance_id" {
  value = aws_instance.free_tier.id
}

output "ami_id" {
  description = "The AMI ID used for the EC2 instance"
  value       = data.aws_ami.amazon_linux.id
}

output "s3_bucket_forecast_raw" {
  value = aws_s3_bucket.forecast_raw.bucket
}

output "s3_bucket_forecast_proccessed" {
  value = aws_s3_bucket.forecast_processed.bucket
}

output "forecast_etl_glue_arn" {
  description = "ARN of the Glue job for forecast_etl"
  value       = aws_glue_job.forecast_etl.arn
}
