terraform {
  # RBAC resources need a recent 1.x spacelift provider.
  required_version = ">= 1.3"

  required_providers {
    spacelift = {
      # `~> 1.0` resolves 1.0.0, which has no spacelift_role_attachment — the one object that
      # makes this whole root work.
      source  = "spacelift-io/spacelift"
      version = "~> 1.52"
    }
  }
}

# Must be a root-admin identity (injected admin-stack token or SPACELIFT_API_KEY_*); see README.
provider "spacelift" {}
