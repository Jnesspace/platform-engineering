variable "stack_id" {
  description = "ID of the stack whose workspace (and credentials) the task runs in."
  type        = string
}

variable "command" {
  description = "Command to run, e.g. 'aws secretsmanager rotate-secret --secret-id my-app-secret'."
  type        = string
}

variable "cron" {
  description = "Cron expression for the task. Default: daily 05:00."
  type        = string
  default     = "0 5 * * *"
}

variable "timezone" {
  description = "Timezone the cron is expressed in."
  type        = string
  default     = "UTC"
}
