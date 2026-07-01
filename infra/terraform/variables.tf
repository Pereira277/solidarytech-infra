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
  description = "Project name used as prefix for all resources"
  type        = string
  default     = "solidarytech"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "production"
}

# ---------- Networking ----------

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_public_a_cidr" {
  description = "CIDR block for public subnet in AZ a"
  type        = string
  default     = "10.0.1.0/24"
}

variable "subnet_public_b_cidr" {
  description = "CIDR block for public subnet in AZ b"
  type        = string
  default     = "10.0.2.0/24"
}

variable "subnet_private_a_cidr" {
  description = "CIDR block for private subnet in AZ a (EKS nodes)"
  type        = string
  default     = "10.0.11.0/24"
}

variable "subnet_private_b_cidr" {
  description = "CIDR block for private subnet in AZ b (EKS nodes)"
  type        = string
  default     = "10.0.12.0/24"
}

variable "subnet_db_a_cidr" {
  description = "CIDR block for database subnet in AZ a (RDS)"
  type        = string
  default     = "10.0.21.0/24"
}

variable "subnet_db_b_cidr" {
  description = "CIDR block for database subnet in AZ b (RDS)"
  type        = string
  default     = "10.0.22.0/24"
}

# ---------- EKS ----------

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "solidarytech-cluster"
}

variable "eks_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.32"
}

variable "node_instance_type" {
  description = "EC2 instance type for EKS worker nodes"
  type        = string
  default     = "t3.medium"
}

# ---------- RDS ----------

variable "rds_instance_class" {
  description = "RDS instance class for PostgreSQL databases"
  type        = string
  default     = "db.t3.micro"
}

variable "ngo_db_username" {
  description = "Master username for the ngo PostgreSQL RDS instance"
  type        = string
  default     = "solidarytech"
}

variable "ngo_db_password" {
  description = "Master password for the ngo PostgreSQL RDS instance — pass via TF_VAR_ngo_db_password"
  type        = string
  sensitive   = true
}

variable "donation_db_username" {
  description = "Master username for the donation PostgreSQL RDS instance"
  type        = string
  default     = "solidarytech"
}

variable "donation_db_password" {
  description = "Master password for the donation PostgreSQL RDS instance — pass via TF_VAR_donation_db_password"
  type        = string
  sensitive   = true
}
