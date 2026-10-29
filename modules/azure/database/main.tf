# Opinionated small-tier Postgres flexible server: TLS 1.2 required, zero firewall rules, backups retained, connection logging on. CMK, Entra auth and diagnostics optional.

locals {
  server_name = "${lower(var.name)}-pg"

  use_cmk = var.cmk_key_vault_key_id != null
}

# Minted only when password auth is on: in Entra-only mode a generated password is a credential
# nobody uses, sitting in state and an output for no reason.
resource "random_password" "admin" {
  count = var.password_auth_enabled ? 1 : 0

  length  = 24
  special = false
}

resource "azurerm_postgresql_flexible_server" "this" {
  name                   = local.server_name
  resource_group_name    = var.resource_group_name
  location               = var.location
  version                = var.postgres_version
  administrator_login    = var.password_auth_enabled ? var.admin_username : null
  administrator_password = var.password_auth_enabled ? random_password.admin[0].result : null
  sku_name               = var.sku_name
  storage_mb             = var.storage_mb
  tags                   = var.tags

  # A delegated subnet means private-IP only; without one the server keeps a public endpoint that no
  # firewall rule opens by default.
  delegated_subnet_id           = var.delegated_subnet_id
  private_dns_zone_id           = var.private_dns_zone_id
  public_network_access_enabled = var.delegated_subnet_id == null

  # Retention alone is not recoverability: flexible server does PITR across the whole window.
  backup_retention_days        = var.backup_retention_days
  geo_redundant_backup_enabled = var.geo_redundant_backup_enabled
  auto_grow_enabled            = true

  authentication {
    password_auth_enabled         = var.password_auth_enabled
    active_directory_auth_enabled = var.entra_auth_enabled
    tenant_id                     = var.entra_auth_enabled ? var.entra_tenant_id : null
  }

  dynamic "high_availability" {
    for_each = var.high_availability_mode == null ? [] : [var.high_availability_mode]

    content {
      mode = high_availability.value
    }
  }

  # Azure encrypts the server at rest regardless; this only moves key ownership to the caller.
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
      key_vault_key_id                  = var.cmk_key_vault_key_id
      primary_user_assigned_identity_id = var.cmk_user_assigned_identity_id
    }
  }

  lifecycle {
    precondition {
      condition     = var.cmk_key_vault_key_id == null || var.cmk_user_assigned_identity_id != null
      error_message = "cmk_key_vault_key_id requires cmk_user_assigned_identity_id: flexible server reaches a customer key only through a user-assigned identity."
    }

    precondition {
      condition     = !var.entra_auth_enabled || var.entra_tenant_id != null
      error_message = "entra_auth_enabled requires entra_tenant_id."
    }

    precondition {
      condition     = var.password_auth_enabled || var.entra_auth_enabled
      error_message = "At least one of password_auth_enabled or entra_auth_enabled must be true, or nothing can log in."
    }

    # Entra-only mode without an Entra administrator creates a server nobody can administer:
    # the password path is off and no Entra principal has been granted admin.
    precondition {
      condition     = var.password_auth_enabled || !var.entra_auth_enabled || (var.entra_admin_object_id != null && var.entra_admin_principal_name != null)
      error_message = "entra-only mode (password_auth_enabled = false, entra_auth_enabled = true) requires entra_admin_object_id + entra_admin_principal_name so somebody can actually administer the server."
    }

    precondition {
      condition     = var.entra_admin_object_id == null || var.entra_admin_principal_name != null
      error_message = "entra_admin_principal_name is required when entra_admin_object_id is set."
    }

    # A public-endpoint server with zero firewall rules is provisioned but unreachable — nothing
    # can connect to it. (The zero-rule default is right; creating it in that state is not.)
    precondition {
      condition     = var.delegated_subnet_id != null || length(var.allowed_cidr_blocks) > 0
      error_message = "No path to the server: without delegated_subnet_id the endpoint is public, and allowed_cidr_blocks is empty so no firewall rule opens it. Add one or the other."
    }
  }
}

# The Entra admin is what makes the password-free path usable: flexible server grants no Entra
# principal any database rights until one is named administrator.
resource "azurerm_postgresql_flexible_server_active_directory_administrator" "this" {
  count = var.entra_auth_enabled && var.entra_admin_object_id != null ? 1 : 0

  server_name         = azurerm_postgresql_flexible_server.this.name
  resource_group_name = azurerm_postgresql_flexible_server.this.resource_group_name
  tenant_id           = var.entra_tenant_id
  object_id           = var.entra_admin_object_id
  principal_name      = var.entra_admin_principal_name
  principal_type      = var.entra_admin_principal_type
}

resource "azurerm_postgresql_flexible_server_database" "this" {
  name      = var.database_name
  server_id = azurerm_postgresql_flexible_server.this.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# require_secure_transport is the switch that makes TLS mandatory rather than merely offered.
resource "azurerm_postgresql_flexible_server_configuration" "this" {
  for_each = var.server_configurations

  name      = each.key
  server_id = azurerm_postgresql_flexible_server.this.id
  value     = each.value
}

# Each CIDR becomes one firewall rule; the list is empty by default, so nothing can connect.
resource "azurerm_postgresql_flexible_server_firewall_rule" "allowed" {
  for_each = { for r in var.allowed_cidr_blocks : r.name => r.cidr }

  name             = each.key
  server_id        = azurerm_postgresql_flexible_server.this.id
  start_ip_address = cidrhost(each.value, 0)
  end_ip_address   = cidrhost(each.value, -1)
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  count = var.log_analytics_workspace_id == null ? 0 : 1

  name                       = "${local.server_name}-diag"
  target_resource_id         = azurerm_postgresql_flexible_server.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = var.diagnostic_log_category_group
  }
}
