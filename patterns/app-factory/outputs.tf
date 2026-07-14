# Consumed by a downstream deploy layer (k8s, a later rung).

output "resource_access" {
  description = "Map of provisioned resource (\"<primitive>/<name>\") => its `access` object."
  sensitive   = true
  value = merge(
    { for k, m in module.object_storage : "object_storage/${k}" => m.access },
    { for k, m in module.secrets : "secrets/${k}" => m.access },
    { for k, m in module.database : "database/${k}" => m.access },
    { for k, m in module.compute : "compute/${k}" => m.access },
  )
}

output "resource_ids" {
  description = "Non-sensitive companion map: resource key => primary id (ARN / resource id)."
  value = merge(
    { for k, m in module.object_storage : "object_storage/${k}" => m.id },
    { for k, m in module.secrets : "secrets/${k}" => m.id },
    { for k, m in module.database : "database/${k}" => m.id },
    { for k, m in module.compute : "compute/${k}" => m.id },
  )
}

output "app_role_arn" {
  description = "ARN of the single app IAM role aggregating every module's least-privilege grant."
  value       = aws_iam_role.app.arn
}
