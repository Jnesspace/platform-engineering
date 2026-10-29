# Opinionated private blob storage: HTTPS-only at TLS 1.2, no anonymous access, blob + container soft delete, versioning, double encryption at rest. CMK and diagnostics optional.

locals {
  # Storage account names: 3-24 chars, lowercase letters and numbers only.
  account_name = substr(replace(lower(var.name), "/[^a-z0-9]/", ""), 0, 24)

  use_cmk = var.cmk_key_vault_key_id != null
}

resource "azurerm_storage_account" "this" {
  name                     = local.account_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = var.account_replication_type
  tags                     = var.tags

  # Azure encrypts every account at rest; infrastructure encryption adds a second, service-managed layer.
  infrastructure_encryption_enabled = var.infrastructure_encryption_enabled

  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = var.shared_access_key_enabled
  public_network_access_enabled   = var.public_network_access_enabled

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = var.blob_soft_delete_days
    }

    container_delete_retention_policy {
      days = var.container_soft_delete_days
    }
  }

  # A user-assigned identity is mandatory for account CMK; the platform supplies it, this module never mints one.
  dynamic "identity" {
    for_each = local.use_cmk ? [1] : []

    content {
      type         = "UserAssigned"
      identity_ids = [var.cmk_user_assigned_identity_id]
    }
  }

  dynamic "customer_managed_key" {
    for_each = local.use_cmk ? [1] : []

    content {
      key_vault_key_id          = var.cmk_key_vault_key_id
      user_assigned_identity_id = var.cmk_user_assigned_identity_id
    }
  }

  dynamic "network_rules" {
    for_each = var.network_rules_default_action == "Deny" ? [1] : []

    content {
      default_action             = "Deny"
      bypass                     = var.network_rules_bypass
      ip_rules                   = var.allowed_ip_rules
      virtual_network_subnet_ids = var.allowed_subnet_ids
    }
  }

  lifecycle {
    precondition {
      condition     = length(local.account_name) >= 3
      error_message = "name must contain at least 3 letters or digits: the storage account name is derived by stripping every other character, and Azure requires 3-24."
    }

    precondition {
      condition     = var.cmk_key_vault_key_id == null || var.cmk_user_assigned_identity_id != null
      error_message = "cmk_key_vault_key_id requires cmk_user_assigned_identity_id: Azure account-level CMK is only accessible through a user-assigned identity."
    }
  }
}

resource "azurerm_storage_container" "this" {
  name                  = var.container_name
  storage_account_name  = azurerm_storage_account.this.name
  container_access_type = "private"
}

# Blob data-plane reads/writes/deletes are only auditable through a diagnostic setting.
resource "azurerm_monitor_diagnostic_setting" "blob" {
  count = var.log_analytics_workspace_id == null ? 0 : 1

  name                       = "${local.account_name}-blob-diag"
  target_resource_id         = "${azurerm_storage_account.this.id}/blobServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = var.diagnostic_log_category_group
  }
}
