output "state_bucket" {
  description = "Name of the S3 bucket that stores the Terraform state of every configuration."
  value       = aws_s3_bucket.state.bucket
}
