variable "name" {
  description = "Logical name; used as the Secrets Manager secret name."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9/_+=.@-]{1,512}$", var.name))
    error_message = "name must be 1-512 chars of letters, digits or /_+=.@- (Secrets Manager naming rules)."
  }
}

variable "tags" {
  description = "Tags applied to every resource this module creates."
  type        = map(string)
  default     = {}
}

variable "initial_value" {
  description = "Optional initial secret value. When empty, only the (empty) secret shell is created and the value is set out-of-band."
  type        = string
  default     = ""
  sensitive   = true
}

variable "rotation_days" {
  description = "When > 0, generate the secret value in-module and rotate it every N days (replaces initial_value). 0 disables rotation."
  type        = number
  default     = 0

  validation {
    condition     = var.rotation_days >= 0 && var.rotation_days <= 365
    error_message = "rotation_days must be between 0 and 365."
  }
}

variable "generated_value_length" {
  description = "Length of the value generated when rotation_days > 0."
  type        = number
  default     = 32

  validation {
    condition     = var.generated_value_length >= 16 && var.generated_value_length <= 256
    error_message = "generated_value_length must be between 16 and 256."
  }
}

variable "kms_key_arn" {
  description = "Customer-managed KMS key ARN encrypting this secret. Empty falls back to the AWS-managed aws/secretsmanager key — the secret is encrypted either way. When set, iam_policy_json also grants the app kms:Decrypt on it, without which every read 403s."
  type        = string
  default     = ""

  validation {
    condition     = var.kms_key_arn == "" || can(regex("^arn:aws[a-z-]*:kms:", var.kms_key_arn))
    error_message = "kms_key_arn must be empty or a KMS key ARN (arn:aws:kms:...)."
  }
}

variable "recovery_window_in_days" {
  description = "Recovery window before a deleted secret is destroyed. Defaults to the production-safe 30; 0 deletes immediately and is the demo escape hatch (a non-zero window keeps the name reserved and blocks re-creating it)."
  type        = number
  default     = 30

  validation {
    condition     = var.recovery_window_in_days == 0 || (var.recovery_window_in_days >= 7 && var.recovery_window_in_days <= 30)
    error_message = "recovery_window_in_days must be 0 (immediate delete) or between 7 and 30."
  }
}

variable "enforce_tls_resource_policy" {
  description = "Attach a resource policy denying any Secrets Manager call to this secret that does not use TLS."
  type        = bool
  default     = true
}
