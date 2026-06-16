output "bucket_name" {
  description = "S3 state bucket name — use this in the infra/terraform backend configuration"
  value       = aws_s3_bucket.terraform_state.id
}

output "bucket_arn" {
  description = "ARN of the Terraform state S3 bucket"
  value       = aws_s3_bucket.terraform_state.arn
}
