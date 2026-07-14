variable "name" {
  description = "Logical name; used for the Cloud SQL instance name."
  type        = string
}

variable "labels" {
  description = "Labels applied to the instance (as user_labels)."
  type        = map(string)
  default     = {}
}

variable "project" {
  description = "GCP project ID. Defaults to the provider's project."
  type        = string
  default     = null
}

variable "region" {
  description = "Region for the Cloud SQL instance."
  type        = string
  default     = "us-central1"
}

variable "database_name" {
  description = "Name of the initial database created on the instance."
  type        = string
  default     = "app"
}

variable "deletion_protection" {
  description = "Protect the instance from terraform destroy."
  type        = bool
  default     = false
}
