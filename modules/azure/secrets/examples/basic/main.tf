terraform {
  required_version = ">= 1.4"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

module "secrets" {
  source = "../.."

  name = "demo-app-secrets"
}

output "id" {
  value = module.secrets.id
}

output "access" {
  value = module.secrets.access
}
