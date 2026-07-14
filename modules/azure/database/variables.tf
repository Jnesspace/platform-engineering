variable "name" {
  description = "Logical name for this database. Used to derive the flexible server name."
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources that support them."
  type        = map(string)
  default     = {}
}

variable "resource_group_name" {
  description = "Resource group to create the server in. Must already exist."
  type        = string
  default     = "app-factory-rg"
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "eastus"
}

variable "postgres_version" {
  description = "PostgreSQL major version."
  type        = string
  default     = "15"
}

variable "admin_username" {
  description = "Administrator login for the server."
  type        = string
  default     = "appadmin"
}

variable "database_name" {
  description = "Name of the database created on the server."
  type        = string
  default     = "app"
}

variable "sku_name" {
  description = "Flexible server SKU (small burstable tier by default)."
  type        = string
  default     = "B_Standard_B1ms"
}

variable "storage_mb" {
  description = "Server storage in MB (smallest supported size by default)."
  type        = number
  default     = 32768
}
