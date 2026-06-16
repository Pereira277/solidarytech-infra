data "aws_caller_identity" "current" {}

locals {
  common_tags = {
    Project     = "SolidaryTech"
    Environment = "production"
    Owner       = "lucas"
    CostCenter  = "NGO-Core"
  }
}

resource "aws_ecr_repository" "ngo" {
  name                 = "solidarytech-ngo"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(local.common_tags, {
    Name = "solidarytech-ngo"
  })
}

resource "aws_ecr_repository" "donation" {
  name                 = "solidarytech-donation"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(local.common_tags, {
    Name = "solidarytech-donation"
  })
}

resource "aws_ecr_repository" "volunteer" {
  name                 = "solidarytech-volunteer"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(local.common_tags, {
    Name = "solidarytech-volunteer"
  })
}
