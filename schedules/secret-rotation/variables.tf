variable "stack_id" {
  description = "ID of the service stack to re-apply (e.g. an app-factory or nonadmin-launcher-vended stack)."
  type        = string
}

variable "name" {
  description = "Name of the schedule as shown in Spacelift."
  type        = string
  default     = "secret-rotation"
}

variable "cron" {
  description = "Cron expression for the re-apply. Default: weekly, Sunday 03:00."
  type        = string
  default     = "0 3 * * 0"
}

variable "timezone" {
  description = "Timezone the cron is expressed in."
  type        = string
  default     = "UTC"
}
