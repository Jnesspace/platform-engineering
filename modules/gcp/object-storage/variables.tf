variable "name" {
  description = "Logical name; used to derive the bucket name (must be globally unique)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._-]{1,61}[a-z0-9]$", var.name)) && !startswith(var.name, "goog")
    error_message = "name must be 3-63 chars, lowercase letters, digits, dots, hyphens or underscores, start and end alphanumeric, and must not start with \"goog\" (GCS naming rules)."
  }
}

variable "labels" {
  description = "Labels applied to the bucket."
  type        = map(string)
  default     = {}
}

variable "project" {
  description = "GCP project ID. Defaults to the provider's project."
  type        = string
  default     = null
}

variable "location" {
  description = "Bucket location."
  type        = string
  default     = "US"
}

variable "storage_class" {
  description = "Default storage class for new objects."
  type        = string
  default     = "STANDARD"

  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE", "MULTI_REGIONAL", "REGIONAL"], var.storage_class)
    error_message = "storage_class must be one of STANDARD, NEARLINE, COLDLINE, ARCHIVE, MULTI_REGIONAL, REGIONAL."
  }
}

variable "force_destroy" {
  description = "Allow deleting the bucket even if it contains objects. Keep false outside of throwaway environments."
  type        = bool
  default     = false
}

variable "kms_key_name" {
  description = "Cloud KMS CryptoKey resource name for CMEK (projects/.../locations/.../keyRings/.../cryptoKeys/...). Null uses Google-managed keys — the bucket is encrypted at rest either way. The key must live in the bucket's location and grant roles/cloudkms.cryptoKeyEncrypterDecrypter to the GCS service agent."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_name == null || can(regex("^projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$", var.kms_key_name))
    error_message = "kms_key_name must be null or a full CryptoKey resource name."
  }
}

variable "access_log_bucket" {
  description = "Bucket receiving GCS usage/storage logs. Null disables access logging; a bucket must not log to itself."
  type        = string
  default     = null
}

variable "access_log_prefix" {
  description = "Object prefix for delivered logs. Null uses the bucket name."
  type        = string
  default     = null
}

variable "soft_delete_retention_seconds" {
  description = "Soft-delete retention for deleted objects, in seconds. GCS accepts 0 (off) or 604800-7776000 (7-90 days); defaults to 7 days."
  type        = number
  default     = 604800

  validation {
    condition     = var.soft_delete_retention_seconds == 0 || (var.soft_delete_retention_seconds >= 604800 && var.soft_delete_retention_seconds <= 7776000)
    error_message = "soft_delete_retention_seconds must be 0 (disabled) or between 604800 (7 days) and 7776000 (90 days)."
  }
}

variable "noncurrent_version_expiration_days" {
  description = "Delete noncurrent (ARCHIVED) object versions after N days. 0 disables the rule."
  type        = number
  default     = 90

  validation {
    condition     = var.noncurrent_version_expiration_days >= 0 && var.noncurrent_version_expiration_days <= 3650
    error_message = "noncurrent_version_expiration_days must be between 0 and 3650."
  }
}

variable "abort_incomplete_multipart_upload_days" {
  description = "Abort (and stop billing for) incomplete multipart uploads after N days."
  type        = number
  default     = 7

  validation {
    condition     = var.abort_incomplete_multipart_upload_days >= 1 && var.abort_incomplete_multipart_upload_days <= 365
    error_message = "abort_incomplete_multipart_upload_days must be between 1 and 365."
  }
}
