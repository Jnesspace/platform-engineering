output "id" {
  description = "Storage account resource id."
  value       = azurerm_storage_account.this.id
}

output "name" {
  description = "Storage account name actually created."
  value       = azurerm_storage_account.this.name
}

output "endpoint" {
  description = "Primary blob service endpoint."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "access" {
  description = "How an app reaches this resource: container + endpoint, and the RBAC role/scope to assign."
  value = {
    account       = azurerm_storage_account.this.name
    container     = azurerm_storage_container.this.name
    blob_endpoint = azurerm_storage_account.this.primary_blob_endpoint
    role          = "Storage Blob Data Contributor"
    scope         = azurerm_storage_account.this.id
  }
}
