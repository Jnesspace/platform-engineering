variable "name" {
  description = "Logical name for this secret. Used to derive the key vault name and to name the secret itself."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,127}$", var.name))
    error_message = "name must contain only letters, digits and hyphens (Key Vault secret naming rules)."
  }

  validation {
    condition     = length(replace(lower(var.name), "/[^a-z0-9-]/", "")) >= 3
    error_message = "name must yield at least 3 valid vault-name characters: the vault name is derived by stripping everything but letters, digits and hyphens, and Azure requires 3-24."
  }
}

variable "tags" {
  description = "Tags applied to all resources that support them."
  type        = map(string)
  default     = {}
}

variable "resource_group_name" {
  description = "Resource group to create the key vault in. Must already exist."
  type        = string
  default     = "app-factory-rg"
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "eastus"
}

variable "initial_value" {
  description = "Initial secret value; empty skips creating the secret resource entirely. Treated as a one-time seed: the module ignores later changes to it, so rotate out-of-band after provisioning (a future apply will never revert that rotation)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "content_type" {
  description = "Content type hint stored alongside the secret, e.g. \"text/plain\" or \"application/json\"."
  type        = string
  default     = "text/plain"
}

variable "expiration_date" {
  description = "RFC 3339 expiry for the secret, e.g. \"2027-01-01T00:00:00Z\". Null means it never expires; an expiry is what forces rotation to actually happen."
  type        = string
  default     = null

  validation {
    condition     = var.expiration_date == null || can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$", var.expiration_date))
    error_message = "expiration_date must be null or an RFC 3339 UTC timestamp like 2027-01-01T00:00:00Z."
  }
}

variable "sku_name" {
  description = "Key Vault SKU. premium backs keys with an HSM; standard is software-protected."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "premium"], var.sku_name)
    error_message = "sku_name must be standard or premium."
  }
}

variable "purge_protection_enabled" {
  description = "Block permanent erasure of a deleted vault or secret until the soft-delete window expires. Defaults to the production-safe value; see the README before flipping it for demos — it also blocks reusing the vault name."
  type        = bool
  default     = true
}

variable "soft_delete_retention_days" {
  description = "Days a deleted vault stays recoverable. Azure allows 7-90; 90 is the platform default and the safest."
  type        = number
  default     = 90

  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "soft_delete_retention_days must be between 7 and 90."
  }
}

variable "enable_rbac_authorization" {
  description = "Govern data-plane access with Azure RBAC instead of vault access policies. False by default because with RBAC on, the Terraform identity needs a Key Vault Secrets Officer role assignment before it can write the secret — a binding this module will not create. RBAC is the recommended production mode."
  type        = bool
  default     = false
}

variable "caller_secret_permissions" {
  description = "Secret permissions granted to the Terraform caller in access-policy mode. Only used when enable_rbac_authorization is false. Purge is deliberately absent from the default: it is the one permission that defeats soft-delete, this module's central protection — add it only for a teardown workflow."
  type        = list(string)
  default     = ["Get", "List", "Set", "Delete"]
}

variable "public_network_access_enabled" {
  description = "Allow the vault endpoint to be reached from public networks. True by default so a Terraform run can write the secret; set false once you provision through a private endpoint."
  type        = bool
  default     = true
}

variable "network_acls_default_action" {
  description = "Firewall posture. Allow by default because the Terraform run writing the secret reaches the vault data plane from a worker with an unpredictable IP; set Deny plus allowed_ip_rules / allowed_subnet_ids once you know where your runners live."
  type        = string
  default     = "Allow"

  validation {
    condition     = contains(["Allow", "Deny"], var.network_acls_default_action)
    error_message = "network_acls_default_action must be Allow or Deny."
  }
}

variable "network_acls_bypass" {
  description = "Traffic exempt from the firewall when network_acls_default_action is Deny."
  type        = string
  default     = "AzureServices"

  validation {
    condition     = contains(["AzureServices", "None"], var.network_acls_bypass)
    error_message = "network_acls_bypass must be AzureServices or None."
  }
}

variable "allowed_ip_rules" {
  description = "Public IPv4 addresses or CIDRs allowed through the firewall. Only used when network_acls_default_action is Deny. Internet-wide CIDRs are rejected at plan time."
  type        = set(string)
  default     = []

  validation {
    condition     = !contains(var.allowed_ip_rules, "0.0.0.0/0")
    error_message = "allowed_ip_rules must not contain 0.0.0.0/0."
  }
}

variable "allowed_subnet_ids" {
  description = "Virtual network subnet ids allowed through the firewall. Only used when network_acls_default_action is Deny."
  type        = set(string)
  default     = []
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace receiving Key Vault audit logs — every secret read shows up there and nowhere else. Null disables diagnostics; this module never creates a workspace of its own."
  type        = string
  default     = null
}

variable "diagnostic_log_category_group" {
  description = "Diagnostic category group to ship. audit is the AuditEvent subset; allLogs adds policy evaluation."
  type        = string
  default     = "audit"

  validation {
    condition     = contains(["allLogs", "audit"], var.diagnostic_log_category_group)
    error_message = "diagnostic_log_category_group must be allLogs or audit."
  }
}
