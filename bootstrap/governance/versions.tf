terraform {
  # strcontains() (engine detection in policies.tf) needs 1.5; the repo standardises on 1.5.7.
  required_version = ">= 1.5.7"

  required_providers {
    spacelift = {
      # spacelift_policy.engine_type and the RBAC resources need a modern 1.x; `~> 1.0` alone
      # would happily resolve 1.0.0, which has neither.
      source  = "spacelift-io/spacelift"
      version = "~> 1.52"
    }
  }
}

# Must be a ROOT-ADMIN identity: policies are account-level objects. See README.
provider "spacelift" {}
