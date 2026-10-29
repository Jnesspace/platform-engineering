variable "name" {
  description = "Logical name; used as the secret id."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.name))
    error_message = "name must be 1-255 chars of letters, digits, hyphens or underscores (Secret Manager secret-id rules)."
  }
}

variable "labels" {
  description = "Labels applied to the secret."
  type        = map(string)
  default     = {}
}

variable "project" {
  description = "GCP project ID. Defaults to the provider's project."
  type        = string
  default     = null
}

variable "initial_value" {
  description = "Optional initial secret value. If set, a first secret version is created."
  type        = string
  default     = ""
  sensitive   = true
}

variable "kms_key_name" {
  description = "Cloud KMS CryptoKey resource name for CMEK. Null uses Google-managed keys — the secret is encrypted at rest either way. With auto replication the key must be global/multi-region and grant roles/cloudkms.cryptoKeyEncrypterDecrypter to the Secret Manager service agent."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_name == null || can(regex("^projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$", var.kms_key_name))
    error_message = "kms_key_name must be null or a full CryptoKey resource name."
  }
}

variable "version_destroy_ttl" {
  description = "Delay before a destroyed secret version is actually erased, as a seconds string (\"86400s\"). Defaults to 24h — the production-safe recovery window. Null disables delayed destruction; Secret Manager's minimum is 24h."
  type        = string
  default     = "86400s"

  validation {
    condition     = var.version_destroy_ttl == null || can(regex("^[0-9]+s$", var.version_destroy_ttl))
    error_message = "version_destroy_ttl must be null or a seconds string like \"86400s\"."
  }
}
