variable "name" {
  description = "Logical name; used as the secret id."
  type        = string
}

variable "labels" {
  description = "Labels applied to the secret."
  type        = map(string)
  default     = {}
}

variable "project" {
  description = "GCP project ID. Defaults to the provider's project."
  type        = string
  default     = null
}

variable "initial_value" {
  description = "Optional initial secret value. If set, a first secret version is created."
  type        = string
  default     = ""
  sensitive   = true
}
