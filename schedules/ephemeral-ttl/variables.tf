variable "stack_id" {
  description = "ID of the ephemeral stack to delete."
  type        = string
}

variable "ttl_hours" {
  description = "Delete the stack this many hours after this config is first applied. Ignored when delete_at is set."
  type        = number
  default     = 72
}

variable "delete_at" {
  description = "Optional explicit deletion time as a unix timestamp; overrides ttl_hours."
  type        = number
  default     = null
}

variable "delete_resources" {
  description = "Also destroy the stack's managed resources, not just the stack."
  type        = bool
  default     = true
}
