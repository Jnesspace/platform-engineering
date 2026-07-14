# Provider CONFIG lives here in the root, never in the modules. All three are
# declared so cloud choice is a data change (platform.yaml), not a code change;
# unused providers configure fine and create nothing.
provider "aws" {
  region = var.region
}

provider "azurerm" {
  features {}
}

provider "google" {
  project = var.project
  zone    = var.zone
}
