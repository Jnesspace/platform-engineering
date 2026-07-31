# Space and stack slugs feed roles/ (governed_spaces) and bootstrap/governance; they are not secrets.
output "environments" {
  value       = { for k, m in module.env : k => { space = m.space_id, stack = m.app_factory_stack_id } }
  description = "Per env: its Space and app-factory stack. Both env Spaces inherit root, so root-published policies already reach them."
}
