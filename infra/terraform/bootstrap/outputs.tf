output "state_bucket" {
  description = "Name of the S3 bucket that stores the Terraform state of every configuration."
  value       = aws_s3_bucket.state.bucket
}

output "plan_role_arn" {
  description = "ARN of the role that pull request workflows assume to run terraform plan."
  value       = aws_iam_role.plan.arn
}
