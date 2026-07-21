# Drift detection on a cron; reconcile = true also triggers a tracked run when drift is found.

resource "spacelift_drift_detection" "this" {
  stack_id  = var.stack_id
  schedule  = var.schedule
  reconcile = var.reconcile
  timezone  = var.timezone
}
