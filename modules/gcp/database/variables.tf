variable "name" {
  description = "Logical name; used for the Cloud SQL instance name."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,96}[a-z0-9]$", var.name))
    error_message = "name must be 2-98 chars, start with a lowercase letter, contain only lowercase letters, digits and hyphens, and not end with a hyphen (Cloud SQL instance naming rules)."
  }
}

variable "labels" {
  description = "Labels applied to the instance (as user_labels)."
  type        = map(string)
  default     = {}
}

variable "project" {
  description = "GCP project ID. Defaults to the provider's project."
  type        = string
  default     = null
}

variable "region" {
  description = "Region for the Cloud SQL instance."
  type        = string
  default     = "us-central1"
}

variable "database_version" {
  description = "Cloud SQL PostgreSQL version."
  type        = string
  default     = "POSTGRES_15"

  validation {
    condition     = can(regex("^POSTGRES_[0-9]{1,2}$", var.database_version))
    error_message = "database_version must be a POSTGRES_<major> value, e.g. POSTGRES_15. This module only provisions PostgreSQL."
  }
}

variable "tier" {
  description = "Machine tier. Small shared-core tier by default."
  type        = string
  default     = "db-f1-micro"
}

variable "edition" {
  description = "Cloud SQL edition. ENTERPRISE is the only edition the shared-core tiers support."
  type        = string
  default     = "ENTERPRISE"

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "edition must be ENTERPRISE or ENTERPRISE_PLUS."
  }
}

variable "availability_type" {
  description = "ZONAL or REGIONAL. Zonal by default because REGIONAL roughly doubles cost; REGIONAL is the production answer and is required by the shared-core tiers' larger siblings for an SLA."
  type        = string
  default     = "ZONAL"

  validation {
    condition     = contains(["ZONAL", "REGIONAL"], var.availability_type)
    error_message = "availability_type must be ZONAL or REGIONAL."
  }
}

variable "disk_type" {
  description = "Data disk type."
  type        = string
  default     = "PD_SSD"

  validation {
    condition     = contains(["PD_SSD", "PD_HDD"], var.disk_type)
    error_message = "disk_type must be PD_SSD or PD_HDD."
  }
}

variable "database_name" {
  description = "Name of the initial database created on the instance."
  type        = string
  default     = "app"

  validation {
    condition     = can(regex("^[a-zA-Z_][a-zA-Z0-9_-]{0,62}$", var.database_name))
    error_message = "database_name must start with a letter or underscore and contain only letters, digits, underscores or hyphens (max 63 chars)."
  }
}

variable "deletion_protection" {
  description = "Protect the instance from deletion, both in Terraform and via the Cloud SQL API. Defaults to the production-safe value; set false for demo teardown (and note both guards flip together)."
  type        = bool
  default     = true
}

variable "ssl_mode" {
  description = "Transport requirement for client connections. ENCRYPTED_ONLY rejects plaintext; TRUSTED_CLIENT_CERTIFICATE_REQUIRED additionally demands a client cert."
  type        = string
  default     = "ENCRYPTED_ONLY"

  validation {
    condition     = contains(["ENCRYPTED_ONLY", "TRUSTED_CLIENT_CERTIFICATE_REQUIRED"], var.ssl_mode)
    error_message = "ssl_mode must be ENCRYPTED_ONLY or TRUSTED_CLIENT_CERTIFICATE_REQUIRED. ALLOW_UNENCRYPTED_AND_ENCRYPTED is not offered by this module."
  }
}

variable "private_network" {
  description = "VPC self-link for a private-IP instance. When set the public IP is dropped entirely; requires a configured private services access range in that VPC."
  type        = string
  default     = null

  validation {
    condition     = var.private_network == null || can(regex("^projects/[^/]+/global/networks/[^/]+$", var.private_network))
    error_message = "private_network must be null or a network resource name like projects/<project>/global/networks/<network>."
  }
}

variable "authorized_networks" {
  description = "Public CIDRs allowed to reach the instance. Empty (the default) means nothing on the internet can connect even though a public IP exists. Internet-wide CIDRs are rejected at plan time."
  type = list(object({
    name = string
    cidr = string
  }))
  default = []

  validation {
    condition     = alltrue([for n in var.authorized_networks : n.cidr != "0.0.0.0/0"])
    error_message = "authorized_networks must not contain 0.0.0.0/0. Use private_network, or the Cloud SQL Auth Proxy, for broad access."
  }

  validation {
    condition     = alltrue([for n in var.authorized_networks : can(cidrnetmask(n.cidr))])
    error_message = "each authorized_networks cidr must be a valid IPv4 CIDR."
  }
}

variable "kms_key_name" {
  description = "Cloud KMS CryptoKey resource name for CMEK. Null uses Google-managed keys — the instance is encrypted at rest either way. The key must be in the instance region and grant roles/cloudkms.cryptoKeyEncrypterDecrypter to the Cloud SQL service account."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_name == null || can(regex("^projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$", var.kms_key_name))
    error_message = "kms_key_name must be null or a full CryptoKey resource name."
  }
}

variable "point_in_time_recovery_enabled" {
  description = "Keep write-ahead logs so the instance can be restored to any moment in the retention window."
  type        = bool
  default     = true
}

variable "transaction_log_retention_days" {
  description = "Days of write-ahead logs kept for point-in-time recovery."
  type        = number
  default     = 7

  validation {
    condition     = var.transaction_log_retention_days >= 1 && var.transaction_log_retention_days <= 35
    error_message = "transaction_log_retention_days must be between 1 and 35."
  }
}

variable "retained_backups" {
  description = "Number of automated backups retained."
  type        = number
  default     = 7

  validation {
    condition     = var.retained_backups >= 1 && var.retained_backups <= 365
    error_message = "retained_backups must be between 1 and 365."
  }
}

variable "backup_start_time" {
  description = "Daily UTC start time for automated backups, HH:MM."
  type        = string
  default     = "03:00"

  validation {
    condition     = can(regex("^[0-2][0-9]:[0-5][0-9]$", var.backup_start_time))
    error_message = "backup_start_time must be HH:MM in UTC."
  }
}

variable "database_flags" {
  description = "PostgreSQL flags set on the instance. The defaults are the audit baseline: connections, disconnections and DDL statements logged. Entries are merged wholesale, so re-state the defaults if you override."
  type        = map(string)

  default = {
    log_connections    = "on"
    log_disconnections = "on"
    log_statement      = "ddl"
  }
}
