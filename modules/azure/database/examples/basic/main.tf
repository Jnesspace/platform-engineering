terraform {
  required_version = ">= 1.4"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.116.0, < 4.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}

module "database" {
  source = "../.."

  name = "demo-app"

  # The module refuses a public-endpoint server with no firewall rule at all.
  allowed_cidr_blocks = [{ name = "office", cidr = "203.0.113.0/24" }]
}

output "id" {
  value = module.database.id
}

output "access" {
  value     = module.database.access
  sensitive = true
}
