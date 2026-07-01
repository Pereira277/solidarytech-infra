provider "aws" {
  region = var.aws_region
}

# DR provider — Velero backup bucket lives in us-east-2
provider "aws" {
  alias  = "dr"
  region = var.aws_region_dr
}
