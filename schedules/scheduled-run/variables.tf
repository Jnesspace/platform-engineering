variable "stack_id" {
  description = "ID of the stack to run on schedule."
  type        = string
}

variable "name" {
  description = "Name of the schedule as shown in Spacelift."
  type        = string
  default     = "nightly-run"
}

variable "cron" {
  description = "Cron expression for the run. Default: daily 01:00."
  type        = string
  default     = "0 1 * * *"
}

variable "timezone" {
  description = "Timezone the cron is expressed in."
  type        = string
  default     = "UTC"
}
