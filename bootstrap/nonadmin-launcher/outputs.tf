output "platform_space_id" {
  value       = spacelift_space.platform.id
  description = "Governance plane Space. Pass to roles/ governed_spaces — it holds exactly one stack, so a requester bound here can trigger only the engine."
}

output "team_space_id" {
  value       = spacelift_space.team.id
  description = "Product team Space the engine provisions into. Add to bootstrap/governance policy_spaces: it does not inherit, so root policies cannot reach it."
}

output "engine_stack_id" {
  value       = spacelift_stack.onboarding_engine.id
  description = "The admin-owned engine stack."
}

# The one object that grants admin anywhere in this design.
output "engine_role_binding_id" {
  value       = spacelift_role_attachment.engine_admin_on_team.id
  description = "The single privileged object: Space-admin bound to the engine, scoped to the team Space."
  sensitive   = true
}
