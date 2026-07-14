terraform {
  required_version = ">= 1.4"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # The aws/database module generates its master password with random_password.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}
