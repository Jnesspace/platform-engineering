output "id" {
  description = "Virtual machine resource id."
  value       = azurerm_linux_virtual_machine.this.id
}

output "name" {
  description = "Virtual machine name actually created."
  value       = azurerm_linux_virtual_machine.this.name
}

output "endpoint" {
  description = "Private IP address of the VM. There is no public IP."
  value       = azurerm_linux_virtual_machine.this.private_ip_address
}

output "access" {
  description = "How an app/operator reaches this resource: address + identity, and the RBAC role/scope to assign. No password exists (SSH-key-only). Role hint is least-privilege: Administrator Login covers Entra-based SSH; Virtual Machine Contributor would allow resizing, deleting and re-imaging the VM, which an operator login does not need."
  sensitive   = true
  value = {
    private_ip     = azurerm_linux_virtual_machine.this.private_ip_address
    admin_username = azurerm_linux_virtual_machine.this.admin_username
    admin_password = ""
    role           = "Virtual Machine Administrator Login"
    scope          = azurerm_linux_virtual_machine.this.id
  }
}

output "identity_principal_id" {
  description = "Object id of the VM's system-assigned identity, for role assignments made outside this module. Empty when assign_system_identity is false."
  value       = try(azurerm_linux_virtual_machine.this.identity[0].principal_id, "")
}
