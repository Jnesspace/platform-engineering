# Cron re-apply of the service stack; time_rotating-keyed secrets regenerate once rotation_days elapses.

resource "spacelift_scheduled_run" "rotation" {
  stack_id = var.stack_id
  name     = var.name
  every    = [var.cron]
  timezone = var.timezone
}
