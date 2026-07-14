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
