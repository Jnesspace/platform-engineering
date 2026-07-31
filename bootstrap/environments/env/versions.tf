terraform {
  required_version = ">= 1.4"
  required_providers {
    spacelift = {
      # `~> 1.0` resolves 1.0.0, which predates the attributes this repo relies on; keep every
      # root on the same modern 1.x floor.
      source  = "spacelift-io/spacelift"
      version = "~> 1.52"
    }
  }
}
