variable "name" {
  description = "Logical name for this storage resource. Used to derive the storage account name (lowercased, alphanumeric only)."
  type        = string

  validation {
    condition     = length(replace(lower(var.name), "/[^a-z0-9]/", "")) >= 3
    error_message = "name must contain at least 3 letters or digits: the storage account name is derived by stripping everything else, and Azure requires 3-24 chars."
  }
}

variable "tags" {
  description = "Tags applied to all resources that support them."
  type        = map(string)
  default     = {}
}

variable "resource_group_name" {
  description = "Resource group to create the storage account in. Must already exist."
  type        = string
  default     = "app-factory-rg"
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "eastus"
}

variable "container_name" {
  description = "Name of the blob container created inside the storage account."
  type        = string
  default     = "data"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{1,61}[a-z0-9])$", var.container_name))
    error_message = "container_name must be 3-63 chars, lowercase letters, digits and hyphens, starting and ending alphanumeric."
  }
}

variable "account_replication_type" {
  description = "Replication mode. LRS is the cheap default; ZRS or GZRS is the production answer for anything that must survive a zone or region loss."
  type        = string
  default     = "LRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.account_replication_type)
    error_message = "account_replication_type must be one of LRS, ZRS, GRS, RAGRS, GZRS, RAGZRS."
  }
}

variable "infrastructure_encryption_enabled" {
  description = "Add a second service-managed encryption layer beneath the account key. Can only be set at creation, so changing it replaces the account."
  type        = bool
  default     = true
}

variable "shared_access_key_enabled" {
  description = "Allow shared-key (account key) authentication. False by default: the account key bypasses Entra RBAC entirely, which is the opposite of this module's access model. The cost is that azurerm creates the blob container over the data plane with the account key by default, so with this false the provider needs storage_use_azuread = true (and the caller Storage Blob Data Contributor) or container creation fails loudly at apply. Set true only as a compatibility escape hatch."
  type        = bool
  default     = false
}

variable "public_network_access_enabled" {
  description = "Allow the account endpoints to be reached from public networks. True by default so Terraform can create the container; set false once you provision through a private endpoint."
  type        = bool
  default     = true
}

variable "network_rules_default_action" {
  description = "Firewall posture. Allow by default because the Terraform run creating the container must reach the data plane from a worker with an unpredictable IP; set Deny plus allowed_ip_rules / allowed_subnet_ids once you know where your runners live."
  type        = string
  default     = "Allow"

  validation {
    condition     = contains(["Allow", "Deny"], var.network_rules_default_action)
    error_message = "network_rules_default_action must be Allow or Deny."
  }
}

variable "network_rules_bypass" {
  description = "Traffic exempt from the firewall when network_rules_default_action is Deny."
  type        = set(string)
  default     = ["AzureServices"]

  validation {
    condition     = alltrue([for b in var.network_rules_bypass : contains(["AzureServices", "Logging", "Metrics", "None"], b)])
    error_message = "network_rules_bypass entries must be AzureServices, Logging, Metrics or None."
  }
}

variable "allowed_ip_rules" {
  description = "Public IPv4 addresses or CIDRs allowed through the firewall. Only used when network_rules_default_action is Deny. Internet-wide CIDRs are rejected at plan time."
  type        = set(string)
  default     = []

  validation {
    condition     = !contains(var.allowed_ip_rules, "0.0.0.0/0")
    error_message = "allowed_ip_rules must not contain 0.0.0.0/0."
  }
}

variable "allowed_subnet_ids" {
  description = "Virtual network subnet ids allowed through the firewall. Only used when network_rules_default_action is Deny."
  type        = set(string)
  default     = []
}

variable "blob_soft_delete_days" {
  description = "Retention for soft-deleted blobs, in days."
  type        = number
  default     = 7

  validation {
    condition     = var.blob_soft_delete_days >= 1 && var.blob_soft_delete_days <= 365
    error_message = "blob_soft_delete_days must be between 1 and 365."
  }
}

variable "container_soft_delete_days" {
  description = "Retention for soft-deleted containers, in days."
  type        = number
  default     = 7

  validation {
    condition     = var.container_soft_delete_days >= 1 && var.container_soft_delete_days <= 365
    error_message = "container_soft_delete_days must be between 1 and 365."
  }
}

variable "cmk_key_vault_key_id" {
  description = "Key Vault key id for account-level customer-managed encryption. Null uses Microsoft-managed keys — the account is encrypted at rest either way. Requires cmk_user_assigned_identity_id."
  type        = string
  default     = null
}

variable "cmk_user_assigned_identity_id" {
  description = "User-assigned managed identity the account uses to reach the CMK. Required whenever cmk_key_vault_key_id is set; the identity needs wrap/unwrap/get on the key."
  type        = string
  default     = null
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace receiving blob-service diagnostic logs. Null disables diagnostics — this module never creates a workspace of its own."
  type        = string
  default     = null
}

variable "diagnostic_log_category_group" {
  description = "Diagnostic category group to ship. allLogs is universally supported; audit is the narrower read/write/delete subset."
  type        = string
  default     = "allLogs"

  validation {
    condition     = contains(["allLogs", "audit"], var.diagnostic_log_category_group)
    error_message = "diagnostic_log_category_group must be allLogs or audit."
  }
}
