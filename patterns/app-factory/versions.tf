terraform {
  required_version = ">= 1.4"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # aws/database generates its master password in-module.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}
