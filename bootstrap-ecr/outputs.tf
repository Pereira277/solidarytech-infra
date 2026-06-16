output "account_id" {
  description = "AWS account ID — used to construct ECR push/pull URLs"
  value       = data.aws_caller_identity.current.account_id
}

output "ngo_repository_url" {
  description = "Full ECR repository URL for ngo-service"
  value       = aws_ecr_repository.ngo.repository_url
}

output "donation_repository_url" {
  description = "Full ECR repository URL for donation-service"
  value       = aws_ecr_repository.donation.repository_url
}

output "volunteer_repository_url" {
  description = "Full ECR repository URL for volunteer-service"
  value       = aws_ecr_repository.volunteer.repository_url
}
