variable "stack_id" {
  description = "ID of the stack to check for drift."
  type        = string
}

variable "schedule" {
  description = "Cron expressions for drift checks. Default: every 6 hours."
  type        = list(string)
  default     = ["0 */6 * * *"]
}

variable "reconcile" {
  description = "Trigger a tracked run (re-converge) when drift is detected."
  type        = bool
  default     = false
}

variable "timezone" {
  description = "Timezone the cron is expressed in."
  type        = string
  default     = "UTC"
}
