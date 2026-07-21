variable "name" {
  description = "Logical name; used as the Secrets Manager secret name."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource this module creates."
  type        = map(string)
  default     = {}
}

variable "initial_value" {
  description = "Optional initial secret value. When empty, only the (empty) secret shell is created and the value is set out-of-band."
  type        = string
  default     = ""
  sensitive   = true
}

variable "rotation_days" {
  description = "When > 0, generate the secret value in-module and rotate it every N days (replaces initial_value). 0 disables rotation."
  type        = number
  default     = 0
}
