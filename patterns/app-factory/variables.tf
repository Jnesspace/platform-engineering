variable "shopping_list_file" {
  description = "Path to the app's shopping list (platform.yaml). Relative paths resolve against this directory."
  type        = string
  default     = "../../examples/jimmy-app/platform.yaml"
}

variable "cloud" {
  description = "Which cloud's modules to instantiate: aws | azure | gcp. A `cloud:` key in the shopping list wins over this."
  type        = string
  default     = "aws"

  validation {
    condition     = contains(["aws", "azure", "gcp"], var.cloud)
    error_message = "cloud must be one of: aws, azure, gcp."
  }
}

variable "app_name" {
  description = "Override for the app name. Empty means: use the shopping list's `name:`."
  type        = string
  default     = ""
}

# --- provider context (safe defaults; only the selected cloud's are used) ---

variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "resource_group_name" {
  description = "Azure resource group the app's resources land in (must already exist)."
  type        = string
  default     = "app-factory-rg"
}

variable "project" {
  description = "GCP project ID. Null defers to the provider's ambient configuration."
  type        = string
  default     = null
}

variable "zone" {
  description = "GCP zone for compute resources."
  type        = string
  default     = "us-central1-a"
}
