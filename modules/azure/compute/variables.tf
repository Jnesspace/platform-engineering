variable "name" {
  description = "Logical name for this VM. Used for the VM and NIC names."
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources that support them."
  type        = map(string)
  default     = {}
}

variable "resource_group_name" {
  description = "Resource group to create the VM in. Must already exist."
  type        = string
  default     = "app-factory-rg"
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "eastus"
}

variable "subnet_id" {
  description = "Subnet the NIC attaches to. The default is a placeholder id so the module validates standalone — override it with a real subnet id for any actual deployment."
  type        = string
  default     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/app-factory-rg/providers/Microsoft.Network/virtualNetworks/app-factory-vnet/subnets/default"
}

variable "size" {
  description = "VM size (small burstable tier by default)."
  type        = string
  default     = "Standard_B1s"
}

variable "admin_username" {
  description = "Administrator login for the VM."
  type        = string
  default     = "azureuser"
}
