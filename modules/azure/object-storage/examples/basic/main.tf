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

module "object_storage" {
  source = "../.."

  name = "demo-uploads"
}

output "id" {
  value = module.object_storage.id
}

output "access" {
  value = module.object_storage.access
}
