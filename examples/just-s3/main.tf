# "I just need an S3 bucket" — Path A: a root config calling one module.
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

module "bucket" {
  source = "../../modules/aws/object-storage"
  name   = "acme-uploads"
  tags   = { team = "acme" }
}

output "bucket_name" {
  value = module.bucket.name
}
