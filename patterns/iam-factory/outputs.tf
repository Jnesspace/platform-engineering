output "oidc_provider_arn" {
  value       = local.oidc_provider_arn
  description = "ARN of the Spacelift OIDC provider."
}

output "vended" {
  value = {
    for k in keys(local.services) : k => {
      space_id    = spacelift_space.service[k].id
      role_arn    = aws_iam_role.space[k].arn
      permissions = local.requested_sets[k]
    }
  }
  description = "Map of shopping-list entry => the Space ID, IAM role ARN, and permission sets it vended."
}

output "granted_actions" {
  value       = local.granted_actions
  description = "Per service: the concrete IAM actions its vended role was granted (union of the catalog sets it requested)."
}

output "boundary_policy_arn" {
  value       = aws_iam_policy.boundary.arn
  description = "ARN of the permissions boundary applied to every vended role."
}
