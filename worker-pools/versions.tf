terraform {
  required_version = ">= 1.4"

  required_providers {
    spacelift = {
      # `~> 1.0` resolves 1.0.0, which predates the RBAC and policy-engine attributes this repo
      # needs; keep every root on the same modern 1.x floor.
      source  = "spacelift-io/spacelift"
      version = "~> 1.52"
    }
  }
}

# Must be a root-admin identity: worker pools are account-level objects.
provider "spacelift" {}
