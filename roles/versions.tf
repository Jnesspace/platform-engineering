terraform {
  # terraform_data (the separation-of-duties gate) needs 1.4.
  required_version = ">= 1.4"

  required_providers {
    spacelift = {
      # `~> 1.0` resolves 1.0.0, which has no spacelift_role at all.
      source  = "spacelift-io/spacelift"
      version = "~> 1.52"
    }
  }
}

# Creating and binding roles is root-admin only: you cannot grant a role you do not hold.
provider "spacelift" {}
