output "platform_space_id" {
  value       = spacelift_space.platform.id
  description = "Governance plane Space."
}

output "team_space_id" {
  value       = spacelift_space.team.id
  description = "Product team Space the engine provisions into."
}

output "engine_stack_id" {
  value       = spacelift_stack.onboarding_engine.id
  description = "The admin-owned engine stack."
}

output "engine_role_binding_id" {
  value       = spacelift_role_attachment.engine_admin_on_team.id
  description = "The single privileged object: Space-admin bound to the engine, scoped to the team Space."
}

output "team_consumer_role_id" {
  value       = spacelift_role.team_consumer.id
  description = "Non-admin role to assign to product-team users/groups."
}
