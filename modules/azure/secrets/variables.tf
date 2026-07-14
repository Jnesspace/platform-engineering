variable "name" {
  description = "Logical name for this secret. Used to derive the key vault name and to name the secret itself."
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources that support them."
  type        = map(string)
  default     = {}
}

variable "resource_group_name" {
  description = "Resource group to create the key vault in. Must already exist."
  type        = string
  default     = "app-factory-rg"
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "eastus"
}

variable "initial_value" {
  description = "Initial secret value. Rotate/replace it out-of-band after provisioning."
  type        = string
  default     = "placeholder"
  sensitive   = true
}
