output "delete_at" {
  description = "Resolved unix timestamp at which the stack will be deleted."
  value       = spacelift_scheduled_delete_stack.ttl.at
}
