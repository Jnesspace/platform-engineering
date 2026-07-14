output "id" {
  description = "Flexible server resource id."
  value       = azurerm_postgresql_flexible_server.this.id
}

output "name" {
  description = "Flexible server name actually created."
  value       = azurerm_postgresql_flexible_server.this.name
}

output "endpoint" {
  description = "Server FQDN."
  value       = azurerm_postgresql_flexible_server.this.fqdn
}

output "access" {
  description = "How an app reaches this resource: connection details plus the RBAC role/scope to assign."
  sensitive   = true
  value = {
    host     = azurerm_postgresql_flexible_server.this.fqdn
    port     = 5432
    database = azurerm_postgresql_flexible_server_database.this.name
    username = azurerm_postgresql_flexible_server.this.administrator_login
    password = random_password.admin.result
    role     = "Reader"
    scope    = azurerm_postgresql_flexible_server.this.id
  }
}
