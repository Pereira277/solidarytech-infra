terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }

  # S3 backend provisioned by bootstrap-s3.
  # Re-run `terraform init` whenever AWS credentials are rotated.
  backend "s3" {
    bucket = "solidarytech-terraform-state-354132155257"
    key    = "infra/terraform.tfstate"
    region = "us-east-1"
  }
}
