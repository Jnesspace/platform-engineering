# Opinionated Key Vault holding one secret: purge protection and soft delete on, no template/disk-encryption sharing, TLS is the only transport Azure offers. RBAC, firewall and diagnostics optional.

data "azurerm_client_config" "current" {}

locals {
  # Key vault names: 3-24 chars, letters, numbers and hyphens.
  vault_name = substr(replace(lower(var.name), "/[^a-z0-9-]/", ""), 0, 24)
}

resource "azurerm_key_vault" "this" {
  name                = local.vault_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = var.sku_name
  tags                = var.tags

  # Soft delete is always on in Azure; purge protection is what stops a deleted vault (and its
  # secrets) being erased before the window expires.
  purge_protection_enabled   = var.purge_protection_enabled
  soft_delete_retention_days = var.soft_delete_retention_days

  enable_rbac_authorization     = var.enable_rbac_authorization
  public_network_access_enabled = var.public_network_access_enabled

  # Access policies and RBAC are mutually exclusive; only one of the two can govern the vault.
  dynamic "access_policy" {
    for_each = var.enable_rbac_authorization ? [] : [1]

    content {
      tenant_id          = data.azurerm_client_config.current.tenant_id
      object_id          = data.azurerm_client_config.current.object_id
      secret_permissions = var.caller_secret_permissions
    }
  }

  dynamic "network_acls" {
    for_each = var.network_acls_default_action == "Deny" ? [1] : []

    content {
      default_action             = "Deny"
      bypass                     = var.network_acls_bypass
      ip_rules                   = var.allowed_ip_rules
      virtual_network_subnet_ids = var.allowed_subnet_ids
    }
  }

  lifecycle {
    precondition {
      condition     = length(local.vault_name) >= 3
      error_message = "name must yield at least 3 valid vault-name characters: the vault name is derived by stripping everything but letters, digits and hyphens, and Azure requires 3-24."
    }

    # The derived name must also be VALID, not just long enough: Azure requires a leading
    # letter and forbids trailing/consecutive hyphens, and a truncation to 24 chars can
    # manufacture both from an otherwise fine input name.
    precondition {
      condition     = can(regex("^[a-z][a-z0-9-]{1,22}[a-z0-9]$", local.vault_name)) && !strcontains(local.vault_name, "--")
      error_message = "derived vault name '${local.vault_name}' is invalid: Azure vault names must start with a letter, end with a letter or digit, and contain no consecutive hyphens."
    }
  }
}

# Count-gated on initial_value: an empty seed means "provision the vault only" — creating a
# secret holding the literal "placeholder" is a finding dressed as a default.
resource "azurerm_key_vault_secret" "this" {
  count = var.initial_value != "" ? 1 : 0

  name         = var.name
  key_vault_id = azurerm_key_vault.this.id
  value        = var.initial_value
  content_type = var.content_type

  expiration_date = var.expiration_date

  lifecycle {
    # initial_value is a seed, not the source of truth: rotation happens out-of-band, and
    # without this the next apply reverts the vault to the seed — un-rotating the secret.
    ignore_changes = [value]
  }
}

# Every secret read is an AuditEvent; without a diagnostic setting they go nowhere.
resource "azurerm_monitor_diagnostic_setting" "this" {
  count = var.log_analytics_workspace_id == null ? 0 : 1

  name                       = "${local.vault_name}-diag"
  target_resource_id         = azurerm_key_vault.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = var.diagnostic_log_category_group
  }
}
