variable "aws_region" {
  description = "Primary AWS region"
  type        = string
  default     = "us-east-1"
}

variable "aws_region_dr" {
  description = "AWS region for Disaster Recovery (Velero backup destination)"
  type        = string
  default     = "us-east-2"
}

variable "project" {
  description = "Project name"
  type        = string
  default     = "solidarytech"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "production"
}
