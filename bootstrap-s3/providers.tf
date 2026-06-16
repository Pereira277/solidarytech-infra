terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Local backend: this module cannot depend on the S3 bucket it creates.
  # Do not migrate this backend to S3.
  backend "local" {}
}

provider "aws" {
  region = var.aws_region
}
