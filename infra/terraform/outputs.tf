output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster API server endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "eks_cluster_ca" {
  description = "EKS cluster certificate authority data (base64)"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "ngo_db_endpoint" {
  description = "RDS endpoint for ngo-service (host:port)"
  value       = aws_db_instance.ngo.endpoint
}

output "donation_db_endpoint" {
  description = "RDS endpoint for donation-service (host:port)"
  value       = aws_db_instance.donation.endpoint
}

output "sqs_queue_url" {
  description = "SQS queue URL for donation-service events"
  value       = aws_sqs_queue.donation_events.url
}

output "dynamodb_table_name" {
  description = "DynamoDB table name for volunteer-service"
  value       = aws_dynamodb_table.volunteers.name
}

output "velero_bucket_name" {
  description = "S3 bucket name for Velero DR backups (us-east-2)"
  value       = aws_s3_bucket.velero.bucket
}

output "ecr_ngo_url" {
  description = "ECR repository URL for ngo-service"
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/solidarytech-ngo"
}

output "ecr_donation_url" {
  description = "ECR repository URL for donation-service"
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/solidarytech-donation"
}

output "ecr_volunteer_url" {
  description = "ECR repository URL for volunteer-service"
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/solidarytech-volunteer"
}
