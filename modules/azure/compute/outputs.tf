output "id" {
  description = "Virtual machine resource id."
  value       = azurerm_linux_virtual_machine.this.id
}

output "name" {
  description = "Virtual machine name actually created."
  value       = azurerm_linux_virtual_machine.this.name
}

output "endpoint" {
  description = "Private IP address of the VM."
  value       = azurerm_linux_virtual_machine.this.private_ip_address
}

output "access" {
  description = "How an app/operator reaches this resource: address + credentials, and the RBAC role/scope to assign."
  sensitive   = true
  value = {
    private_ip     = azurerm_linux_virtual_machine.this.private_ip_address
    admin_username = azurerm_linux_virtual_machine.this.admin_username
    admin_password = random_password.admin.result
    role           = "Virtual Machine Contributor"
    scope          = azurerm_linux_virtual_machine.this.id
  }
}
