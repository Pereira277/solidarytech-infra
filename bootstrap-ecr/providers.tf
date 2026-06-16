terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Local backend: permanent alongside bootstrap-s3.
  # Do not destroy this state; ECR repository URLs are referenced by all CI/CD pipelines.
  backend "local" {}
}

provider "aws" {
  region = var.aws_region
}
