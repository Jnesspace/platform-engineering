variable "name" {
  description = "Logical name; used as the bucket name. Must be globally unique and S3-compatible (lowercase, hyphens)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.name)) && !can(regex("\\.\\.", var.name))
    error_message = "name must be a valid S3 bucket name: 3-63 chars, lowercase letters, digits, dots or hyphens, starting and ending alphanumeric, no consecutive dots."
  }
}

variable "tags" {
  description = "Tags applied to every resource this module creates."
  type        = map(string)
  default     = {}
}

variable "force_destroy" {
  description = "Allow destroying the bucket even when it still holds objects. Keep false outside of throwaway environments."
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "Customer-managed KMS key ARN for default bucket encryption (SSE-KMS). Empty falls back to the AWS-managed S3 key (SSE-S3) — either way the bucket is encrypted at rest. When set, iam_policy_json also grants the app the key permissions it needs at runtime."
  type        = string
  default     = ""

  validation {
    condition     = var.kms_key_arn == "" || can(regex("^arn:aws[a-z-]*:kms:", var.kms_key_arn))
    error_message = "kms_key_arn must be empty or a KMS key ARN (arn:aws:kms:...)."
  }
}

variable "access_log_bucket" {
  description = "Bucket that receives S3 server access logs. Empty disables access logging. The target bucket must already permit logging.s3.amazonaws.com to write."
  type        = string
  default     = ""

  validation {
    condition     = var.access_log_bucket == "" || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.access_log_bucket))
    error_message = "access_log_bucket must be empty or a valid S3 bucket name."
  }
}

variable "access_log_prefix" {
  description = "Key prefix for delivered access logs. Empty derives s3-access-logs/<name>/."
  type        = string
  default     = ""
}

variable "noncurrent_version_expiration_days" {
  description = "Delete noncurrent object versions after N days. 0 disables the rule (versions kept forever)."
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
