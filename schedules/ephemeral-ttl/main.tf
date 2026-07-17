# Auto-teardown of an ephemeral stack: at an explicit timestamp, or ttl_hours after first apply.

# Anchors the TTL at first apply; only used when delete_at is unset.
resource "time_offset" "ttl" {
  offset_hours = var.ttl_hours
}

resource "spacelift_scheduled_delete_stack" "ttl" {
  stack_id         = var.stack_id
  at               = coalesce(var.delete_at, time_offset.ttl.unix)
  delete_resources = var.delete_resources
}
