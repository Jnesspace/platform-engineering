# "I need a bucket, a database, and a secret" — Path A: one root, several modules.
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

locals {
  tags = { team = "acme", app = "acme-billing" }
}

module "bucket" {
  source = "../../modules/aws/object-storage"
  name   = "acme-billing-uploads"
  tags   = local.tags
}

module "db" {
  source = "../../modules/aws/database"
  name   = "acme-billing"
  tags   = local.tags
}

module "secret" {
  source = "../../modules/aws/secrets"
  name   = "acme-billing-app"
  tags   = local.tags
}

output "bucket_name" {
  value = module.bucket.name
}

output "db_endpoint" {
  value = module.db.endpoint
}

output "app_secret" {
  value = module.secret.id
}
