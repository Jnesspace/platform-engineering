# Nightly tracked run of a stack on a cron.

resource "spacelift_scheduled_run" "nightly" {
  stack_id = var.stack_id
  name     = var.name
  every    = [var.cron]
  timezone = var.timezone
}
