# Arbitrary command in the stack's workspace on a cron.

resource "spacelift_scheduled_task" "this" {
  stack_id = var.stack_id
  command  = var.command
  every    = [var.cron]
  timezone = var.timezone
}
