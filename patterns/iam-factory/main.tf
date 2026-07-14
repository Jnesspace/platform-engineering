# iam-factory: turns each services/*.yaml into a Space + OIDC-pinned scoped IAM role + auto-attached context; capped by the catalog gate (plan) and permissions boundary (runtime).

locals {
  issuer   = "${var.account_subdomain}.app.spacelift.io"
  audience = "${var.account_subdomain}.app.spacelift.io"

  # Match both extensions so a .yml file isn't silently ignored.
  service_files = setunion(
    fileset("${path.module}/services", "*.yaml"),
    fileset("${path.module}/services", "*.yml"),
  )
  services = {
    for f in local.service_files :
    trimsuffix(trimsuffix(f, ".yaml"), ".yml") => yamldecode(file("${path.module}/services/${f}"))
  }

  # catalog.yaml IS the allowed universe; services may only pick names from it.
  catalog = yamldecode(file("${path.module}/catalog.yaml"))

  requested_sets = {
    for k, v in local.services : k => try(v.permissions, var.default_permission_sets)
  }

  unknown_sets = {
    for k, sets in local.requested_sets :
    k => [for s in sets : s if !contains(keys(local.catalog), s)]
  }

  granted_actions = {
    for k, sets in local.requested_sets :
    k => distinct(flatten([for s in sets : local.catalog[s] if contains(keys(local.catalog), s)]))
  }
}

# OIDC provider: created once, or referenced if it already exists.
data "tls_certificate" "spacelift" {
  url = "https://${local.issuer}"
}

resource "aws_iam_openid_connect_provider" "spacelift" {
  count = var.create_oidc_provider ? 1 : 0

  url             = "https://${local.issuer}"
  client_id_list  = [local.audience]
  thumbprint_list = [data.tls_certificate.spacelift.certificates[0].sha1_fingerprint]
}

data "aws_iam_openid_connect_provider" "existing" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://${local.issuer}"
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.spacelift[0].arn : data.aws_iam_openid_connect_provider.existing[0].arn
}

# Permissions boundary: runtime hard cap on every vended role — no IAM/org/account tampering even if the catalog would allow it.
resource "aws_iam_policy" "boundary" {
  name        = "spacelift-space-boundary"
  description = "Permissions boundary for Spacelift per-Space roles minted by the platform factory."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowEverythingByDefault"
        Effect   = "Allow"
        Action   = "*"
        Resource = "*"
      },
      {
        Sid    = "DenyPrivilegeEscalationAndControlPlane"
        Effect = "Deny"
        Action = [
          "iam:*",
          "organizations:*",
          "account:*",
          "sts:AssumeRole",
          "sts:AssumeRoleWithSAML",
        ]
        Resource = "*"
      },
    ]
  })
}

# inherit_entities stays true: disabling inheritance is root-admin-only and this factory runs with Space-admin (see docs/hardening-backlog.md).
resource "spacelift_space" "service" {
  for_each = local.services

  name             = try(each.value.name, each.key)
  parent_space_id  = try(each.value.parent_space, var.parent_space_id)
  description      = try(each.value.description, "Vended environment for ${each.key}")
  inherit_entities = true
}

# Plan-time gate: off-catalog or zero-permission requests fail before anything is minted (terraform_data needs no credentials).
resource "terraform_data" "permission_gate" {
  for_each = local.services
  input    = local.granted_actions[each.key]

  lifecycle {
    precondition {
      condition     = length(local.unknown_sets[each.key]) == 0
      error_message = "Service '${each.key}' requested permission set(s) not in catalog.yaml: ${join(", ", local.unknown_sets[each.key])}. Allowed sets: ${join(", ", keys(local.catalog))}. Add the set to catalog.yaml (platform review) or fix the request."
    }
    precondition {
      condition     = length(local.granted_actions[each.key]) > 0
      error_message = "Service '${each.key}' resolves to zero permissions. List at least one catalog set under `permissions:`."
    }
    precondition {
      # IAM role name is "spacelift-<slug>" (64-char cap); keep slug clean + short.
      condition     = can(regex("^[a-z0-9-]{1,54}$", each.key))
      error_message = "Service slug '${each.key}' must be lowercase alphanumeric/hyphen and <= 54 chars (the role name is spacelift-<slug>)."
    }
  }
}

# One boundary-capped role per Space; the OIDC `sub` is pinned to that Space, with read+write scopes so one ARN serves plans and applies.
resource "aws_iam_role" "space" {
  for_each = local.services

  depends_on = [terraform_data.permission_gate]

  name                 = "spacelift-${each.key}"
  permissions_boundary = aws_iam_policy.boundary.arn
  description          = "Vended role for Spacelift Space ${spacelift_space.service[each.key].id}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = local.oidc_provider_arn }
      Condition = {
        StringEquals = {
          "${local.issuer}:aud" = local.audience
        }
        StringLike = {
          "${local.issuer}:sub" = [
            "space:${spacelift_space.service[each.key].id}:*:scope:write",
            "space:${spacelift_space.service[each.key].id}:*:scope:read",
          ]
        }
      }
    }]
  })
}

# Scoped inline policy: exactly the requested catalog sets; the boundary still caps it.
resource "aws_iam_role_policy" "space" {
  for_each = local.services

  name = "spacelift-${each.key}-scoped"
  role = aws_iam_role.space[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "CatalogGrant"
        Effect   = "Allow"
        Action   = local.granted_actions[each.key]
        Resource = "*"
      },
      {
        # sts:GetCallerIdentity baseline so the AWS provider can init.
        Sid      = "ProviderBaseline"
        Effect   = "Allow"
        Action   = ["sts:GetCallerIdentity"]
        Resource = "*"
      },
    ]
  })
}

# Auto-attached context per Space hands TF_VAR_aws_role_arn to stacks labeled `aws-oidc`.
resource "spacelift_context" "aws" {
  for_each = local.services

  name        = "aws-${each.key}"
  space_id    = spacelift_space.service[each.key].id
  description = "Auto-attached AWS OIDC role for the ${each.key} Space, managed by the platform factory."
  labels      = ["autoattach:aws-oidc"]
}

resource "spacelift_environment_variable" "role_arn" {
  for_each = local.services

  context_id = spacelift_context.aws[each.key].id
  name       = "TF_VAR_aws_role_arn"
  value      = aws_iam_role.space[each.key].arn
  write_only = false
}

# IAM is global, but the consuming stack's AWS provider still needs a region to init.
resource "spacelift_environment_variable" "aws_region" {
  for_each = local.services

  context_id = spacelift_context.aws[each.key].id
  name       = "AWS_DEFAULT_REGION"
  value      = var.default_aws_region
  write_only = false
}
