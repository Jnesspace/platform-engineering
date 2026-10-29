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

module "secrets" {
  source = "../.."

  name = "demo-app-secrets"

  # Empty initial_value (the default) provisions the vault only; set one to also seed the secret.
  initial_value = "change-me-out-of-band"
}

output "id" {
  value = module.secrets.id
}

output "access" {
  value = module.secrets.access
}
