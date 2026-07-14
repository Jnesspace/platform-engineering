terraform {
  # terraform_data (the permission gate) needs >= 1.4.
  required_version = ">= 1.4"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    spacelift = {
      source  = "spacelift-io/spacelift"
      version = "~> 1.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

# AWS creds come from the AWS integration attached to this stack.
provider "aws" {}

# Spacelift creds are injected automatically because this stack is administrative.
provider "spacelift" {}
