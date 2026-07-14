variable "name" {
  description = "Logical name for this storage resource. Used to derive the storage account name (lowercased, alphanumeric only)."
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources that support them."
  type        = map(string)
  default     = {}
}

variable "resource_group_name" {
  description = "Resource group to create the storage account in. Must already exist."
  type        = string
  default     = "app-factory-rg"
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "eastus"
}

variable "container_name" {
  description = "Name of the blob container created inside the storage account."
  type        = string
  default     = "data"
}
