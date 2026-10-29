variable "name" {
  description = "Logical name for this database. Used to derive the flexible server name (<name>-pg)."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,58}[a-zA-Z0-9]$", var.name))
    error_message = "name must be 2-60 chars, start and end alphanumeric, and contain only letters, digits and hyphens (the server name appends \"-pg\" and Azure caps it at 63)."
  }
}

variable "tags" {
  description = "Tags applied to all resources that support them."
  type        = map(string)
  default     = {}
}

variable "resource_group_name" {
  description = "Resource group to create the server in. Must already exist."
  type        = string
  default     = "app-factory-rg"
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "eastus"
}

variable "postgres_version" {
  description = "PostgreSQL major version."
  type        = string
  default     = "15"

  validation {
    condition     = can(regex("^[0-9]{2}$", var.postgres_version))
    error_message = "postgres_version must be a two-digit major version, e.g. \"15\"."
  }
}

variable "admin_username" {
  description = "Administrator login for the server. The password is generated in-module and surfaced only through the sensitive access output."
  type        = string
  default     = "appadmin"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{2,62}$", var.admin_username)) && !contains(["azure_superuser", "azure_pg_admin", "admin", "administrator", "root", "guest", "public", "postgres"], lower(var.admin_username))
    error_message = "admin_username must be 3-63 lowercase chars starting with a letter (letters, digits, underscores) and must not be a name Azure reserves (azure_superuser, azure_pg_admin, admin, administrator, root, guest, public, postgres)."
  }
}

variable "database_name" {
  description = "Name of the database created on the server."
  type        = string
  default     = "app"

  validation {
    condition     = can(regex("^[a-zA-Z_][a-zA-Z0-9_-]{0,62}$", var.database_name))
    error_message = "database_name must start with a letter or underscore and contain only letters, digits, underscores or hyphens (max 63 chars)."
  }
}

variable "sku_name" {
  description = "Flexible server SKU (small burstable tier by default)."
  type        = string
  default     = "B_Standard_B1ms"

  validation {
    condition     = can(regex("^(B|GP|MO)_", var.sku_name))
    error_message = "sku_name must start with B_ (burstable), GP_ (general purpose) or MO_ (memory optimised)."
  }
}

variable "storage_mb" {
  description = "Server storage in MB (smallest supported size by default)."
  type        = number
  default     = 32768

  validation {
    condition     = contains([32768, 65536, 131072, 262144, 524288, 1048576, 2097152, 4193280, 4194304, 8388608, 16777216, 33553408], var.storage_mb)
    error_message = "storage_mb must be one of the sizes flexible server supports (32768, 65536, 131072, 262144, 524288, 1048576, ...)."
  }
}

variable "server_configurations" {
  description = "Server parameters applied after creation. The defaults are the security baseline: TLS required at 1.2 or better, connections and disconnections logged. Entries are applied wholesale, so re-state the defaults if you override."
  type        = map(string)

  default = {
    require_secure_transport = "on"
    ssl_min_protocol_version = "TLSV1.2"
    log_connections          = "on"
    log_disconnections       = "on"
  }

  validation {
    # lookup with an unsafe sentinel, not try(..., "on"): an absent key used to PASS validation,
    # so a caller replacing the map wholesale could drop TLS enforcement by omission and the
    # access output would still advertise sslmode = "require".
    condition     = lower(lookup(var.server_configurations, "require_secure_transport", "off")) == "on"
    error_message = "server_configurations must include require_secure_transport = \"on\" (the default carries it — re-state it when overriding): this module does not ship a configuration that accepts plaintext PostgreSQL connections."
  }
}

variable "allowed_cidr_blocks" {
  description = "Public CIDRs allowed to reach the server, one firewall rule each. Empty (the default) means nothing can connect. Internet-wide CIDRs — including Azure's 0.0.0.0/0 \"allow all Azure services\" trick — are rejected at plan time."
  type = list(object({
    name = string
    cidr = string
  }))
  default = []

  validation {
    condition     = alltrue([for r in var.allowed_cidr_blocks : r.cidr != "0.0.0.0/0"])
    error_message = "allowed_cidr_blocks must not contain 0.0.0.0/0. Use delegated_subnet_id for private access."
  }

  validation {
    condition     = alltrue([for r in var.allowed_cidr_blocks : can(cidrhost(r.cidr, 0))])
    error_message = "each allowed_cidr_blocks cidr must be a valid IPv4 CIDR."
  }

  validation {
    condition     = alltrue([for r in var.allowed_cidr_blocks : can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,78}$", r.name))])
    error_message = "each allowed_cidr_blocks name must be 1-79 chars of letters, digits and hyphens, starting alphanumeric (Azure firewall rule naming rules)."
  }
}

variable "delegated_subnet_id" {
  description = "Delegated subnet for a private-IP server. When set the public endpoint is disabled entirely; the subnet must be delegated to Microsoft.DBforPostgreSQL/flexibleServers."
  type        = string
  default     = null
}

variable "private_dns_zone_id" {
  description = "Private DNS zone for the private-IP server's FQDN. Required by Azure whenever delegated_subnet_id is set."
  type        = string
  default     = null
}

variable "backup_retention_days" {
  description = "Automated backup retention, which is also the point-in-time-restore window."
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 7 and 35 (7 is the Azure minimum, so backups cannot be turned off)."
  }
}

variable "geo_redundant_backup_enabled" {
  description = "Replicate backups to the paired region. Off by default because it roughly doubles backup cost and cannot be changed after creation; on is the production answer."
  type        = bool
  default     = false
}

variable "high_availability_mode" {
  description = "ZoneRedundant or SameZone HA. Null disables HA; the burstable (B_) SKUs do not support it at all."
  type        = string
  default     = null

  validation {
    # coalesce with a sentinel, not "== null ||": Terraform evaluates both operands of || even when
    # the first is true, and coalesce treats "" as absent.
    condition     = contains(["ZoneRedundant", "SameZone", "unset"], coalesce(var.high_availability_mode, "unset"))
    error_message = "high_availability_mode must be null, ZoneRedundant or SameZone."
  }
}

variable "password_auth_enabled" {
  description = "Allow PostgreSQL password authentication."
  type        = bool
  default     = true
}

variable "entra_auth_enabled" {
  description = "Allow Microsoft Entra ID authentication, so apps can connect with a managed identity and no stored password. Requires entra_tenant_id."
  type        = bool
  default     = false
}

variable "entra_tenant_id" {
  description = "Entra tenant id for Entra authentication. Required whenever entra_auth_enabled is true."
  type        = string
  default     = null
}

variable "entra_admin_object_id" {
  description = "Object id of the Entra principal made PostgreSQL administrator. Required in entra-only mode (password_auth_enabled = false): without an Entra administrator, a password-free server logs nobody in."
  type        = string
  default     = null
}

variable "entra_admin_principal_name" {
  description = "Display name of the Entra administrator principal (user UPN, group name, or service principal name). Required whenever entra_admin_object_id is set — enforced by a server precondition, since a variable validation may not reference another variable."
  type        = string
  default     = null
}

variable "entra_admin_principal_type" {
  description = "Type of the Entra administrator principal: User, Group, or ServicePrincipal. A Group is the operable choice — admin rights survive individual offboarding."
  type        = string
  default     = "Group"

  validation {
    condition     = contains(["User", "Group", "ServicePrincipal"], var.entra_admin_principal_type)
    error_message = "entra_admin_principal_type must be User, Group, or ServicePrincipal."
  }
}

variable "cmk_key_vault_key_id" {
  description = "Key Vault key id for customer-managed encryption of the server. Null uses Microsoft-managed keys — the server is encrypted at rest either way. Requires cmk_user_assigned_identity_id."
  type        = string
  default     = null
}

variable "cmk_user_assigned_identity_id" {
  description = "User-assigned managed identity the server uses to reach the CMK. Required whenever cmk_key_vault_key_id is set; the identity needs wrap/unwrap/get on the key."
  type        = string
  default     = null
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace receiving server diagnostic logs. Null disables diagnostics — this module never creates a workspace of its own."
  type        = string
  default     = null
}

variable "diagnostic_log_category_group" {
  description = "Diagnostic category group to ship. allLogs is universally supported for flexible server."
  type        = string
  default     = "allLogs"

  validation {
    condition     = contains(["allLogs", "audit"], var.diagnostic_log_category_group)
    error_message = "diagnostic_log_category_group must be allLogs or audit."
  }
}
