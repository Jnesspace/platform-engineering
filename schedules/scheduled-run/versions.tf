terraform {
  required_version = ">= 1.4"

  required_providers {
    spacelift = {
      source  = "spacelift-io/spacelift"
      version = "~> 1.0"
    }
  }
}

# Spacelift creds come from the run's injected token (or SPACELIFT_API_KEY_* locally).
provider "spacelift" {}
