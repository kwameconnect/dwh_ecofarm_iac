output "ec2_instance_id" {
  value = aws_instance.free_tier.id
}

output "s3_bucket_name" {
  value = aws_s3_bucket.free_tier.bucket
}
