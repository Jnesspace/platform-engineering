# Provider config lives in the root, never here. Floor pinned to the release carrying every argument this module sets.
terraform {
  required_version = ">= 1.4"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.40.0, < 6.0.0"
    }
  }
}
