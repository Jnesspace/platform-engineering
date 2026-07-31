# `name` is the cross-root handle; the ULID is here for humans, not for wiring.
output "name" {
  value       = spacelift_worker_pool.elevated.name
  description = "Pass this as elevated_worker_pool_name to every bootstrap root."
}

# Not secret in itself, but it is the one string an attacker needs to aim a run at the private pool.
output "worker_pool_id" {
  value       = spacelift_worker_pool.elevated.id
  description = "ULID of the pool. bootstrap/* resolves this by name instead of consuming it."
  sensitive   = true
}
