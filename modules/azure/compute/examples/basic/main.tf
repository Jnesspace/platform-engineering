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

module "compute" {
  source = "../.."

  name = "demo-vm"
}

output "id" {
  value = module.compute.id
}

output "access" {
  value     = module.compute.access
  sensitive = true
}
