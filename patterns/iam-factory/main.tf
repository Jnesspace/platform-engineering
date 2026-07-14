##############################################################################
# Platform factory ("role + space vending machine")
#
# One admin stack that turns a git-tracked "DevX shopping list" into real
# environments. Drop a services/<name>.yaml file, push, and the next run mints,
# for that service:
#   - a Spacelift Space (child of the platform-admin Space)
#   - a per-Space IAM role trusted only by that Space's OIDC `sub`, granted a
#     scoped policy built from the platform-owned catalog.yaml
#   - an auto-attached context handing the role ARN to every stack in the
#     Space that carries the `aws-oidc` label
#
# Labeled stacks in a Space pick up their role automatically and, thanks to
# the trust policy, can never assume another Space's role no matter what ARN
# they type. What the role can DO is capped twice: the catalog gate (plan-time
# allowlist) and the permissions boundary (runtime hard cap).
##############################################################################

locals {
  issuer   = "${var.account_subdomain}.app.spacelift.io"
  audience = "${var.account_subdomain}.app.spacelift.io"

  # The DevX shopping list: one YAML per requested service/environment.
  # Match both .yaml and .yml so a dev naming a file .yml isn't silently ignored.
  service_files = setunion(
    fileset("${path.module}/services", "*.yaml"),
    fileset("${path.module}/services", "*.yml"),
  )
  services = {
    for f in local.service_files :
    trimsuffix(trimsuffix(f, ".yaml"), ".yml") => yamldecode(file("${path.module}/services/${f}"))
  }

  # Platform-owned catalog: permission-set name -> list of IAM actions.
  # catalog.yaml IS the allowed universe; services may only pick names from it.
  catalog = yamldecode(file("${path.module}/catalog.yaml"))

  # Per service: requested permission-set names (default when YAML omits `permissions`).
  requested_sets = {
    for k, v in local.services : k => try(v.permissions, var.default_permission_sets)
  }

  # Requested set names that are NOT in the catalog -> violations (block the run).
  unknown_sets = {
    for k, sets in local.requested_sets :
    k => [for s in sets : s if !contains(keys(local.catalog), s)]
  }

  # Concrete IAM actions granted to each role = union of requested (valid) sets' actions.
  granted_actions = {
    for k, sets in local.requested_sets :
    k => distinct(flatten([for s in sets : local.catalog[s] if contains(keys(local.catalog), s)]))
  }
}

# ---------------------------------------------------------------------------
# 1. The OIDC provider (created once).
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# 2. The permissions boundary — the un-escapable hard cap. Vended roles carry
#    a per-service scoped policy from the catalog, and the boundary caps even
#    that: no IAM tampering, no touching the OIDC trust, no org/account
#    control. sts:GetCallerIdentity stays allowed so AWS provider init works.
#    Defense in depth on top of the catalog gate below.
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# 3. One Space per shopping-list entry, created under the platform-admin Space.
#    inherit_entities stays ON: DISABLING inheritance is a root-admin-only
#    operation ("only root admins can disable inheritance"), and this factory
#    deliberately runs with Space-admin (not root). Tightening vended-space
#    inheritance to false must therefore be done by the root-admin bootstrap,
#    not here — tracked in docs/hardening-backlog.md.
# ---------------------------------------------------------------------------
resource "spacelift_space" "service" {
  for_each = local.services

  name             = try(each.value.name, each.key)
  parent_space_id  = try(each.value.parent_space, var.parent_space_id)
  description      = try(each.value.description, "Vended environment for ${each.key}")
  inherit_entities = true
}

# ---------------------------------------------------------------------------
# 4. Plan-time enforcement gate. Fails the factory run if any service requested
#    a permission set that isn't in catalog.yaml, or resolves to zero
#    permissions. This is the guardrail: a developer cannot grant a role
#    anything outside the platform-owned catalog, no matter what they put in
#    their YAML. terraform_data is provider/credential-independent, so the
#    gate evaluates before anything is minted.
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# 5. One boundary-capped role per Space. Trust policy pins the OIDC `sub` to
#    this Space only; the StringLike list accepts read- and write-scoped run
#    tokens so plans and applies both work with a single role ARN.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "space" {
  for_each = local.services

  # Gate first: the preconditions above must pass before this role is planned.
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

# ---------------------------------------------------------------------------
# 6. Per-service scoped inline policy: exactly the union of the catalog sets
#    the service requested — nothing more. The boundary above still caps it.
# ---------------------------------------------------------------------------
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
        # Baseline every vended role needs regardless of catalog choice: the AWS
        # provider calls sts:GetCallerIdentity during init. Boundary-safe (the
        # boundary allows it), and least-privilege elsewhere.
        Sid      = "ProviderBaseline"
        Effect   = "Allow"
        Action   = ["sts:GetCallerIdentity"]
        Resource = "*"
      },
    ]
  })
}

# ---------------------------------------------------------------------------
# 7. Automatic wiring: an auto-attached context per Space carrying the role ARN
#    as TF_VAR_aws_role_arn. Stacks in the Space that carry the `aws-oidc`
#    label pick it up automatically (autoattach:aws-oidc).
# ---------------------------------------------------------------------------
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

# Region for the consuming stack's AWS provider (creds come from the role above,
# but the provider still needs a region). IAM is global; this is just to init.
resource "spacelift_environment_variable" "aws_region" {
  for_each = local.services

  context_id = spacelift_context.aws[each.key].id
  name       = "AWS_DEFAULT_REGION"
  value      = var.default_aws_region
  write_only = false
}
