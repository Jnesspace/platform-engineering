# iam-factory: turns each services/*.yaml into a Space + OIDC-pinned scoped IAM role + auto-attached context; capped by the catalog gate (plan) and permissions boundary (runtime).

locals {
  issuer   = "${var.account_subdomain}.app.spacelift.io"
  audience = "${var.account_subdomain}.app.spacelift.io"

  # Match both extensions so a .yml file isn't silently ignored.
  service_files = tolist(setunion(
    fileset("${path.module}/services", "*.yaml"),
    fileset("${path.module}/services", "*.yml"),
  ))
  service_slugs = [for f in local.service_files : trimsuffix(trimsuffix(f, ".yaml"), ".yml")]

  # payments.yaml and payments.yml resolve to the same slug; de-duplicate so request_gate reports it instead of Terraform's raw "Duplicate object key".
  duplicate_slugs = [
    for s in distinct(local.service_slugs) : s
    if length([for t in local.service_slugs : t if t == s]) > 1
  ]
  services = {
    for s in distinct(local.service_slugs) :
    s => yamldecode(file("${path.module}/services/${local.service_files[index(local.service_slugs, s)]}"))
  }
  malformed_services = [for k, v in local.services : k if !can(keys(v))]

  # catalog.yaml IS the allowed universe; services may only pick names from it.
  catalog_raw = yamldecode(file("${path.module}/catalog.yaml"))

  # A set is either a bare action list or { actions: [...], resources: [...] }, so a set can carry resource ARNs without reshaping every other entry. try(), not a conditional: a catalog mixing both forms is a heterogeneous object that won't unify with a fallback.
  catalog = try({
    for k, v in local.catalog_raw : k => {
      actions   = try(tolist(v.actions), try(tolist(v), []))
      resources = try(tolist(v.resources), ["*"])
    }
  }, {})

  malformed_sets = [
    for k, v in local.catalog : k
    if length(v.actions) == 0 || length([for a in v.actions : a if !can(regex("^[a-z0-9-]+:[A-Za-z0-9*]+$", a))]) > 0
  ]

  # Set names become policy Sids, and IAM only accepts alphanumerics there.
  invalid_set_names = [for k in keys(local.catalog) : k if !can(regex("^[a-z0-9][a-z0-9-]*$", k))]

  # The catalog is platform-owned, but a mistake in it is the single biggest blast radius here, so it is gated too.
  forbidden_catalog_actions = distinct(flatten([
    for k, v in local.catalog : [
      for a in v.actions : "${k}: ${a}"
      if length([for p in var.forbidden_catalog_action_prefixes : p if startswith(lower(a), lower(p))]) > 0
    ]
  ]))

  # try() keeps a `permissions:` that isn't a list of strings from erroring inside a local before the gate can report it.
  requested_sets = {
    for k, v in local.services :
    k => try([for s in try(v.permissions, var.default_permission_sets) : tostring(s)], [])
  }
  permissions_wellformed = {
    for k, v in local.services :
    k => can([for s in try(v.permissions, var.default_permission_sets) : tostring(s)])
  }

  unknown_sets = {
    for k, sets in local.requested_sets :
    k => [for s in sets : s if !contains(keys(local.catalog), s)]
  }

  granted_actions = {
    for k, sets in local.requested_sets :
    k => distinct(flatten([for s in sets : local.catalog[s].actions if contains(keys(local.catalog), s)]))
  }

  # Region lock, when configured: the single most effective narrowing of a catalog set that grants on Resource = "*".
  region_condition = length(var.allowed_regions) > 0 ? {
    Condition = { StringEquals = { "aws:RequestedRegion" = var.allowed_regions } }
  } : {}

  # One statement per requested set so each carries its own resources instead of everything sharing a blanket "*".
  granted_statements = {
    for k, sets in local.requested_sets : k => [
      for s in distinct(sets) : merge({
        Sid      = "CatalogSet${replace(title(replace(s, "-", " ")), " ", "")}"
        Effect   = "Allow"
        Action   = local.catalog[s].actions
        Resource = local.catalog[s].resources
      }, local.region_condition)
      if contains(keys(local.catalog), s)
    ]
  }

  # A team-supplied parent_space would otherwise place a vended Space anywhere the factory token can reach, outside the platform-admin subtree.
  allowed_parents   = distinct(concat([var.parent_space_id], var.allowed_parent_space_ids))
  requested_parents = { for k, v in local.services : k => try(tostring(v.parent_space), "") }

  space_names = { for k, v in local.services : k => try(tostring(v.name), k) }
  descriptions = {
    for k, v in local.services : k => try(tostring(v.description), "Vended environment for ${k}")
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

  # Allowlist derived from the catalog: a vended role can never act outside the services the catalog covers, however it is later policy-attached. "allow-all" restores the old denylist-only posture.
  catalog_services       = distinct([for a in flatten([for v in values(local.catalog) : v.actions]) : split(":", a)[0]])
  boundary_allow_actions = var.boundary_mode == "allow-all" ? ["*"] : sort([for s in local.catalog_services : "${s}:*"])

  # Escalation and control-plane actions, denied regardless of mode. sts:AssumeRoleWith* here blocks the SESSION from chaining onward; it does not affect Spacelift assuming the role, which is an unsigned call.
  boundary_denied_actions = distinct(concat([
    "iam:*",
    "organizations:*",
    "account:*",
    "sso:*",
    "sso-directory:*",
    "identitystore:*",
    "sts:AssumeRole",
    "sts:AssumeRoleWithSAML",
    "sts:AssumeRoleWithWebIdentity",
    "sts:GetFederationToken",
  ], var.boundary_extra_denied_actions))
}

# Permissions boundary: runtime hard cap on every vended role — no IAM/org/account tampering even if the catalog would allow it.
resource "aws_iam_policy" "boundary" {
  name        = "spacelift-space-boundary"
  description = "Permissions boundary for Spacelift per-Space roles minted by the platform factory."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = var.boundary_mode == "allow-all" ? "AllowEverythingByDefault" : "AllowOnlyCatalogServices"
        Effect   = "Allow"
        Action   = local.boundary_allow_actions
        Resource = "*"
      },
      {
        Sid      = "DenyPrivilegeEscalationAndControlPlane"
        Effect   = "Deny"
        Action   = local.boundary_denied_actions
        Resource = "*"
      },
      {
        # Services that don't set aws:SecureTransport simply don't match, so this can never deny more than intended.
        Sid      = "DenyUnencryptedTransport"
        Effect   = "Deny"
        Action   = "*"
        Resource = "*"
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },
    ]
  })
}

# Gate the platform-owned catalog itself: a wildcard or an escalation-class action here would flow into every vended role.
resource "terraform_data" "catalog_gate" {
  input = sort(keys(local.catalog))

  lifecycle {
    precondition {
      condition     = length(local.catalog) > 0
      error_message = "catalog.yaml must decode to a non-empty mapping of <set-name> => action list (or { actions = [...], resources = [...] })."
    }
    precondition {
      condition     = length(local.malformed_sets) == 0
      error_message = "catalog.yaml set(s) ${join(", ", local.malformed_sets)} are empty or contain entries that aren't IAM actions of the form <service>:<Action>."
    }
    precondition {
      condition     = length(local.invalid_set_names) == 0
      error_message = "catalog.yaml set name(s) ${join(", ", local.invalid_set_names)} must be lowercase alphanumeric/hyphen: the name becomes a policy Sid, and IAM rejects a Sid containing anything else."
    }
    precondition {
      condition     = length(local.forbidden_catalog_actions) == 0
      error_message = "catalog.yaml grants escalation-class action(s): ${join("; ", local.forbidden_catalog_actions)}. Forbidden prefixes: ${join(", ", var.forbidden_catalog_action_prefixes)}. The permissions boundary would still block these at runtime, but they must not be grantable in the first place."
    }
    precondition {
      condition     = length(setsubtract(var.default_permission_sets, keys(local.catalog))) == 0
      error_message = "default_permission_sets contains set(s) not in catalog.yaml: ${join(", ", setsubtract(var.default_permission_sets, keys(local.catalog)))}. Every service that omits `permissions:` would fail."
    }
  }
}

# Gate the request set as a whole: shape and volume, before any per-service checks.
resource "terraform_data" "request_gate" {
  input = length(local.services)

  lifecycle {
    precondition {
      condition     = length(local.duplicate_slugs) == 0
      error_message = "services/ contains both .yaml and .yml for slug(s): ${join(", ", local.duplicate_slugs)}. One file per service — the slug names the role, so a collision is ambiguous."
    }
    precondition {
      condition     = length(local.malformed_services) == 0
      error_message = "services/ file(s) ${join(", ", local.malformed_services)} must decode to a mapping (name/description/parent_space/permissions)."
    }
    precondition {
      condition     = length(local.services) <= var.max_vended_services
      error_message = "${length(local.services)} services requested; the cap is ${var.max_vended_services} (var.max_vended_services). Each one mints a Space, an IAM role and a context — raise the cap deliberately."
    }
  }
}

# inherit_entities stays true: disabling inheritance is root-admin-only and this factory runs with Space-admin (see docs/hardening-backlog.md).
resource "spacelift_space" "service" {
  for_each = local.services

  depends_on = [terraform_data.catalog_gate, terraform_data.request_gate, terraform_data.permission_gate]

  name             = local.space_names[each.key]
  parent_space_id  = local.requested_parents[each.key] != "" ? local.requested_parents[each.key] : var.parent_space_id
  description      = local.descriptions[each.key]
  inherit_entities = true
}

# Plan-time gate: off-catalog or zero-permission requests fail before anything is minted (terraform_data needs no credentials).
resource "terraform_data" "permission_gate" {
  for_each = local.services
  input    = local.granted_actions[each.key]

  lifecycle {
    precondition {
      condition     = local.permissions_wellformed[each.key]
      error_message = "Service '${each.key}' has a malformed `permissions:` block. It must be a YAML list of catalog set names, e.g. `permissions: [s3-readwrite]` — a bare string or nested mapping is rejected."
    }
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
    precondition {
      # The requester supplies this, and it becomes a Space display name in the platform's own hierarchy.
      condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9 ._-]{0,63}$", local.space_names[each.key]))
      error_message = "Service '${each.key}' has an invalid `name:` ('${local.space_names[each.key]}'). Use alphanumerics, spaces, dots, underscores or hyphens, <= 64 chars, starting alphanumeric."
    }
    precondition {
      condition     = length(local.descriptions[each.key]) <= 200
      error_message = "Service '${each.key}' has a `description:` longer than 200 characters."
    }
    precondition {
      condition     = local.requested_parents[each.key] == "" || contains(local.allowed_parents, local.requested_parents[each.key])
      error_message = "Service '${each.key}' requests parent_space '${local.requested_parents[each.key]}', which is not the factory's Space (${var.parent_space_id}) or in var.allowed_parent_space_ids. A request must not be able to place a vended Space outside the subtree the factory governs."
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
            for scope in var.trust_scopes : "space:${spacelift_space.service[each.key].id}:*:scope:${scope}"
          ]
        }
      }
    }]
  })
}

# Scoped inline policy: one statement per requested catalog set, each with that set's resources; the boundary still caps it.
resource "aws_iam_role_policy" "space" {
  for_each = local.services

  name = "spacelift-${each.key}-scoped"
  role = aws_iam_role.space[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(local.granted_statements[each.key], [
      {
        # sts:GetCallerIdentity baseline so the AWS provider can init; global, so no region condition.
        Sid      = "ProviderBaseline"
        Effect   = "Allow"
        Action   = ["sts:GetCallerIdentity"]
        Resource = "*"
      },
    ])
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
