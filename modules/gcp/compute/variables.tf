variable "name" {
  description = "Logical name; used as the instance name."
  type        = string
}

variable "labels" {
  description = "Labels applied to the instance."
  type        = map(string)
  default     = {}
}

variable "project" {
  description = "GCP project ID. Defaults to the provider's project."
  type        = string
  default     = null
}

variable "zone" {
  description = "Zone for the instance."
  type        = string
  default     = "us-central1-a"
}

variable "image" {
  description = "Boot disk image."
  type        = string
  default     = "debian-cloud/debian-12"
}

variable "network" {
  description = "Network to attach the instance to."
  type        = string
  default     = "default"
}
