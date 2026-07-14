variable "name" {
  description = "Logical name; used to derive the bucket name (must be globally unique)."
  type        = string
}

variable "labels" {
  description = "Labels applied to the bucket."
  type        = map(string)
  default     = {}
}

variable "project" {
  description = "GCP project ID. Defaults to the provider's project."
  type        = string
  default     = null
}

variable "location" {
  description = "Bucket location."
  type        = string
  default     = "US"
}

variable "force_destroy" {
  description = "Allow deleting the bucket even if it contains objects."
  type        = bool
  default     = false
}
