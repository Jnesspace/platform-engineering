# Provider config lives in the root, never here. Floor pinned to the release carrying ip_configuration.ssl_mode.
terraform {
  required_version = ">= 1.4"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.40.0, < 6.0.0"
    }
  }
}
