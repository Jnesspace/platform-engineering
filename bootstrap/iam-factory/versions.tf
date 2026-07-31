terraform {
  required_version = ">= 1.4"

  required_providers {
    spacelift = {
      # `~> 1.0` resolves 1.0.0, which has no spacelift_role_attachment — the one object that
      # makes this whole root work.
      source  = "spacelift-io/spacelift"
      version = "~> 1.52"
    }
  }
}

# Auth via SPACELIFT_API_KEY_ENDPOINT / _ID / _SECRET (a root-admin key).
provider "spacelift" {}
