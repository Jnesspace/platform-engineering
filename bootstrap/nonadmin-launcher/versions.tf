terraform {
  # RBAC resources need a recent 1.x spacelift provider.
  required_version = ">= 1.3"

  required_providers {
    spacelift = {
      source  = "spacelift-io/spacelift"
      version = "~> 1.0"
    }
  }
}

# Must be a root-admin identity (injected admin-stack token or SPACELIFT_API_KEY_*); see README.
provider "spacelift" {}
