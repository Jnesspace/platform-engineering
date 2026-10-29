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
  description = "How an app reaches this resource: connection details plus the RBAC role/scope to assign. Sensitive: carries the generated administrator password when password auth is on (null in Entra-only mode). Role hint: database auth is not Azure RBAC — Reader grants nothing here; connect with a managed identity (entra_auth_enabled) or the admin credentials."
  sensitive   = true
  value = {
    host     = azurerm_postgresql_flexible_server.this.fqdn
    port     = 5432
    database = azurerm_postgresql_flexible_server_database.this.name
    username = azurerm_postgresql_flexible_server.this.administrator_login
    password = one(random_password.admin[*].result)
    role     = "None (database auth, not Azure RBAC)"
    scope    = azurerm_postgresql_flexible_server.this.id
    # require_secure_transport = on means anything less is refused server-side.
    sslmode = "require"
  }
}

output "administrator_password" {
  description = "Generated administrator password, for wiring into a secret store. Null in Entra-only mode. Prefer entra_auth_enabled and a managed identity over handling this at all."
  sensitive   = true
  value       = one(random_password.admin[*].result)
}
