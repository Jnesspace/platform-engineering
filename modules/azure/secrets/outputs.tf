output "id" {
  description = "Key vault resource id."
  value       = azurerm_key_vault.this.id
}

output "name" {
  description = "Key vault name actually created."
  value       = azurerm_key_vault.this.name
}

output "endpoint" {
  description = "Key vault URI."
  value       = azurerm_key_vault.this.vault_uri
}

output "access" {
  description = "How an app reaches this resource: vault/secret reference, and the RBAC role/scope to assign."
  value = {
    vault_uri   = azurerm_key_vault.this.vault_uri
    secret_name = azurerm_key_vault_secret.this.name
    secret_id   = azurerm_key_vault_secret.this.versionless_id
    role        = "Key Vault Secrets User"
    scope       = azurerm_key_vault.this.id
  }
}
