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

module "database" {
  source = "../.."

  name = "demo-app"
}

output "id" {
  value = module.database.id
}

output "access" {
  value     = module.database.access
  sensitive = true
}
