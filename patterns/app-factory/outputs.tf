# What a downstream deploy layer (k8s, later rung) consumes: where everything
# is, and the one role that can reach it.

output "resource_access" {
  description = "Map of provisioned resource (\"<primitive>/<name>\") => its `access` object. Marked sensitive because the Azure database/compute access objects carry credentials."
  sensitive   = true
  value = merge(
    { for k, m in module.aws_object_storage : "object_storage/${k}" => m.access },
    { for k, m in module.aws_secrets : "secrets/${k}" => m.access },
    { for k, m in module.aws_database : "database/${k}" => m.access },
    { for k, m in module.aws_compute : "compute/${k}" => m.access },
    { for k, m in module.azure_object_storage : "object_storage/${k}" => m.access },
    { for k, m in module.azure_secrets : "secrets/${k}" => m.access },
    { for k, m in module.azure_database : "database/${k}" => m.access },
    { for k, m in module.azure_compute : "compute/${k}" => m.access },
    { for k, m in module.gcp_object_storage : "object_storage/${k}" => m.access },
    { for k, m in module.gcp_secrets : "secrets/${k}" => m.access },
    { for k, m in module.gcp_database : "database/${k}" => m.access },
    { for k, m in module.gcp_compute : "compute/${k}" => m.access },
  )
}

output "resource_ids" {
  description = "Non-sensitive companion map: resource key => primary id (ARN / resource id / self link)."
  value = merge(
    { for k, m in module.aws_object_storage : "object_storage/${k}" => m.id },
    { for k, m in module.aws_secrets : "secrets/${k}" => m.id },
    { for k, m in module.aws_database : "database/${k}" => m.id },
    { for k, m in module.aws_compute : "compute/${k}" => m.id },
    { for k, m in module.azure_object_storage : "object_storage/${k}" => m.id },
    { for k, m in module.azure_secrets : "secrets/${k}" => m.id },
    { for k, m in module.azure_database : "database/${k}" => m.id },
    { for k, m in module.azure_compute : "compute/${k}" => m.id },
    { for k, m in module.gcp_object_storage : "object_storage/${k}" => m.id },
    { for k, m in module.gcp_secrets : "secrets/${k}" => m.id },
    { for k, m in module.gcp_database : "database/${k}" => m.id },
    { for k, m in module.gcp_compute : "compute/${k}" => m.id },
  )
}

output "app_role_arn" {
  description = "ARN of the single app IAM role aggregating every AWS module's least-privilege grant. Null on non-AWS clouds."
  value       = one(aws_iam_role.app[*].arn)
}
