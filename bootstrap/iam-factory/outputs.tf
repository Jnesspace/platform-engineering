# Space and stack slugs are inputs to roles/ and bootstrap/governance and are visible to anyone with
# read access, so they stay plain. The role binding is the one privileged object here.
output "platform_admin_space_id" {
  value       = spacelift_space.platform_admin.id
  description = "Admin-plane Space. Pass to roles/ governed_spaces; add to bootstrap/governance policy_spaces only if inherit_entities is false."
}

output "factory_stack_id" {
  value       = spacelift_stack.factory.id
  description = "The privileged factory stack."
}

output "factory_role_binding_id" {
  value       = spacelift_role_attachment.factory_admin.id
  description = "The single privileged object: Space-admin bound to the factory stack, scoped to the admin plane."
  sensitive   = true
}
