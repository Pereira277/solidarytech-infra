variable "aws_region" {
  description = "AWS region where the S3 bucket will be created"
  type        = string
  default     = "us-east-1"
}

variable "bucket_name" {
  description = "Globally unique name for the S3 bucket used to store Terraform state"
  type        = string
}
