output "id" {
  description = "Key vault resource id."
  value       = azurerm_key_vault.this.id
}

output "name" {
  description = "Key vault name actually created."
  value       = azurerm_key_vault.this.name
}

output "endpoint" {
  description = "Key vault URI (HTTPS only)."
  value       = azurerm_key_vault.this.vault_uri
}

output "access" {
  description = "How an app reaches this resource: vault/secret reference, and the RBAC role/scope to assign. References only — the value is never an output. secret_name/secret_id are null when initial_value is empty (no secret resource is created then)."
  value = {
    vault_uri   = azurerm_key_vault.this.vault_uri
    secret_name = try(one(azurerm_key_vault_secret.this[*].name), null)
    secret_id   = try(one(azurerm_key_vault_secret.this[*].versionless_id), null)
    role        = "Key Vault Secrets User"
    scope       = azurerm_key_vault.this.id
  }
}
