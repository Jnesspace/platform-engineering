# Provider config lives in the root, never here. Floor pinned to the release carrying https_traffic_only_enabled (the azurerm 4.x argument name).
terraform {
  required_version = ">= 1.4"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.116.0, < 4.0.0"
    }
  }
}
