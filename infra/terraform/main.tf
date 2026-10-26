# SecureFlow Terraform — HARDENED
# Resolved vulnerabilities: IV-01, IV-02, IV-08, IV-09, IV-10

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "eu-west-2"
}

variable "project" {
  type    = string
  default = "secureflow"
}

variable "environment" {
  type    = string
  default = "dev"
}

# IV-01 Resolved — Injected dynamically at runtime via TF_VAR_db_password or Vault
variable "db_password" {
  description = "Master password for RDS PostgreSQL instances"
  type        = string
  sensitive   = true
}

module "vpc" {
  source      = "./modules/vpc"
  project     = var.project
  environment = var.environment
}

module "iam" {
  source      = "./modules/iam"
  project     = var.project
  environment = var.environment
}

module "s3" {
  source  = "./modules/s3"
  project = var.project
}

module "eks" {
  source             = "./modules/eks"
  project            = var.project
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
}

module "rds" {
  source             = "./modules/rds"
  project            = var.project
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  vpc_cidr_block     = module.vpc.vpc_cidr_block
  db_password        = var.db_password
}