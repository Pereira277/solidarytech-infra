# Resources provisioned progressively in subsequent stages:
#   VPC, subnets, IGW, NAT Gateway
#   EKS cluster and node group
#   RDS (ngo-db, donation-db)
#   DynamoDB (volunteer)
#   SQS (donation events)
#   S3 cross-region for Velero DR (us-east-2)

data "aws_caller_identity" "current" {}

locals {
  common_tags = {
    Project     = "SolidaryTech"
    Environment = var.environment
    Owner       = "lucas"
    CostCenter  = "NGO-Core"
  }
}
