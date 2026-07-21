# "I just need a Postgres database" — Path A: a root config calling one module.
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

module "db" {
  source = "../../modules/aws/database"
  name   = "acme-app"
  tags   = { team = "acme" }
}

output "endpoint" {
  value = module.db.endpoint
}

# host/port/database/secret_ref — credentials live in Secrets Manager.
output "connection" {
  value = module.db.access
}
