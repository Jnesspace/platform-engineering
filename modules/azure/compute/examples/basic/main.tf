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

module "compute" {
  source = "../.."

  name = "demo-vm"

  # Placeholder key so the example plans standalone; replace with a real keypair.
  admin_ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDdddddddddddddddddddddddddddddddddddddddddddd demo"
}

output "id" {
  value = module.compute.id
}

output "access" {
  value     = module.compute.access
  sensitive = true
}
