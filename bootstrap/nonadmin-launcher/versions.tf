terraform {
  # RBAC resources (spacelift_role, spacelift_role_attachment) require a recent
  # 1.x provider; ~> 1.0 resolves to the latest 1.x on a fresh init.
  required_version = ">= 1.3"

  required_providers {
    spacelift = {
      source  = "spacelift-io/spacelift"
      version = "~> 1.0"
    }
  }
}

# Runs with the injected token when executed as an admin stack in `root`, or
# with local SPACELIFT_API_KEY_* credentials. See README for why this must be a
# root-admin identity.
provider "spacelift" {}
