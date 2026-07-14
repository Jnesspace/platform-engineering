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
  sku_name            = "standard"
  tags                = var.tags

  access_policy {
    tenant_id          = data.azurerm_client_config.current.tenant_id
    object_id          = data.azurerm_client_config.current.object_id
    secret_permissions = ["Get", "List", "Set", "Delete", "Purge"]
  }
}

resource "azurerm_key_vault_secret" "this" {
  name         = var.name
  key_vault_id = azurerm_key_vault.this.id
  value        = var.initial_value
}
