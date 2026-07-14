resource "random_password" "admin" {
  length  = 24
  special = false
}

resource "azurerm_postgresql_flexible_server" "this" {
  name                   = "${lower(var.name)}-pg"
  resource_group_name    = var.resource_group_name
  location               = var.location
  version                = var.postgres_version
  administrator_login    = var.admin_username
  administrator_password = random_password.admin.result
  sku_name               = var.sku_name
  storage_mb             = var.storage_mb
  tags                   = var.tags
}

resource "azurerm_postgresql_flexible_server_database" "this" {
  name      = var.database_name
  server_id = azurerm_postgresql_flexible_server.this.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}
