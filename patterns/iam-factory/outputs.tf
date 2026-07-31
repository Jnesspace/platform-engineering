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

# The boundary is the claim the whole pattern rests on, so make it auditable without reading state.
output "boundary_posture" {
  value = {
    mode            = var.boundary_mode
    allowed_actions = local.boundary_allow_actions
    denied_actions  = local.boundary_denied_actions
    region_lock     = var.allowed_regions
  }
  description = "What the permissions boundary actually caps: allowlist mode and its derived allowed actions, the escalation deny list, and any region lock."
}
