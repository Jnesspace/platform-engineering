output "environments" {
  value = { for k, m in module.env : k => { space = m.space_id, stack = m.app_factory_stack_id } }
}
