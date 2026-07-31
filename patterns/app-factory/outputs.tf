# Consumed by a downstream deploy layer (app-deploy); anything carrying a resource ARN is sensitive because those ARNs are exactly what an attacker needs to aim at.

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
  description = "Map of resource key => primary id (ARN / resource id). Sensitive: it carries secret and database ARNs plus the account ID."
  sensitive   = true
  value = merge(
    { for k, m in module.object_storage : "object_storage/${k}" => m.id },
    { for k, m in module.secrets : "secrets/${k}" => m.id },
    { for k, m in module.database : "database/${k}" => m.id },
    { for k, m in module.compute : "compute/${k}" => m.id },
  )
}

# The non-sensitive inventory view: what was vended, without the identifiers.
output "resource_keys" {
  description = "Sorted list of provisioned resource keys (\"<primitive>/<name>\") — safe to show in run logs and dashboards."
  value = sort(concat(
    [for k in keys(module.object_storage) : "object_storage/${k}"],
    [for k in keys(module.secrets) : "secrets/${k}"],
    [for k in keys(module.database) : "database/${k}"],
    [for k in keys(module.compute) : "compute/${k}"],
  ))
}

# The audit view of the security options that were actually applied — a control nobody can see the state
# of is the same problem as a control nobody can reach. Key ARNs and a log-bucket name are not secrets.
output "posture" {
  description = "Security posture the vended resources actually got: CMK per resource (empty = the AWS-managed key), the access-log destination, and whether the teardown escape hatch is on."
  value = {
    kms_key_arns      = local.resolved_kms
    access_log_bucket = var.access_log_bucket
    demo_teardown     = var.demo_teardown
  }
}

output "app_role_arn" {
  description = "ARN of the single app IAM role aggregating every module's least-privilege grant."
  value       = aws_iam_role.app.arn
}

# Lets the deploy stack wire its namespace/ServiceAccount from the factory instead of duplicating the values by hand — a mismatch here is an AccessDenied at runtime.
output "app_role_trust" {
  description = "How the app role can be assumed: trust mode, and for IRSA the exact namespace, ServiceAccount and OIDC `sub` the trust policy pins."
  value = {
    mode            = var.trust_mode
    namespace       = local.k8s_namespace
    service_account = local.k8s_service_account
    oidc_provider   = var.trust_mode == "irsa" ? var.eks_oidc_provider_arn : ""
    oidc_sub        = var.trust_mode == "irsa" ? local.irsa_sub : ""
    oidc_audience   = var.trust_mode == "irsa" ? "sts.amazonaws.com" : ""
  }
}
