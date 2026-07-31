# app-factory (AWS path): composes modules/aws/* from platform.yaml and aggregates their IAM into one app role (iam.tf); each cloud gets its own root because Terraform eagerly configures every declared provider.

locals {
  shopping_list_path = startswith(var.shopping_list_file, "/") ? var.shopping_list_file : "${path.root}/${var.shopping_list_file}"
  # Inline YAML (Blueprint/form path) wins over the file (git path).
  spec = yamldecode(var.shopping_list_yaml != "" ? var.shopping_list_yaml : file(local.shopping_list_path))

  cloud    = try(local.spec.cloud, "aws")
  app_name = var.app_name != "" ? var.app_name : try(local.spec.name, "app")

  # Same precedence as app_name: the stack's value wins, the list's is the GitOps fallback. A blueprint or
  # per-env stack knows the owning team authoritatively; a team's own repo is where it declares one otherwise.
  owner = var.owner != "" ? var.owner : try(tostring(local.spec.owner), "")

  # Never from the list: policies/plan/protect-env-labels.rego treats env:* as a privilege claim, and the
  # Environment tag is the same claim in tag form. It comes from the stack's lane, i.e. from an operator.
  environment = var.environment

  # Environment/Owner/Project are required by policies/plan/enforce-required-tags.rego on every taggable
  # resource; app/managed_by are the engine's own provenance markers and predate it.
  tags = {
    Environment = local.environment
    Owner       = local.owner
    Project     = local.app_name
    app         = local.app_name
    managed_by  = "app-factory"
  }

  resources = try(local.spec.resources, {})
}

# The shopping list is team-supplied, so treat it as untrusted input: everything below feeds shopping_list_guard, which fails the plan with one clear message instead of half-applying.
locals {
  known_kinds = ["object_storage", "secrets", "database", "compute"]

  spec_ok        = can(keys(local.spec))
  resources_ok   = can(keys(local.resources))
  declared_kinds = local.resources_ok ? keys(local.resources) : []
  # A typo like `object-storage` would otherwise be silently ignored — the team thinks they ordered a bucket and got nothing.
  unknown_kinds = [for k in local.declared_kinds : k if !contains(local.known_kinds, k)]

  # Same reasoning one level up: `resource:` or `demo_teardown: true` at the root would otherwise vanish.
  known_top_keys   = ["name", "cloud", "owner", "resources"]
  unknown_top_keys = [for k in try(keys(local.spec), []) : k if !contains(local.known_top_keys, k)]

  # The three tags policies/plan/enforce-required-tags.rego requires. Empty or malformed here means the run
  # is denied later by a policy message that names a resource address rather than the missing input.
  owner_ok       = can(regex("^[a-z0-9]([a-z0-9]|-[a-z0-9])*$", local.owner)) && length(local.owner) <= 40
  environment_ok = can(regex("^[a-z0-9]([a-z0-9]|-[a-z0-9])*$", local.environment)) && length(local.environment) <= 20

  # try() everywhere so a malformed list yields an empty one for the gate to report, rather than erroring inside a local.
  raw   = { for kind in local.known_kinds : kind => try(local.resources[kind], []) }
  names = { for kind in local.known_kinds : kind => try([for r in local.raw[kind] : tostring(r.name)], []) }

  # Fewer resolved names than entries means the kind isn't a list of objects carrying a string `name`.
  malformed_kinds = [
    for kind in local.known_kinds : kind
    if try(length(local.raw[kind]), 0) != length(local.names[kind])
  ]

  duplicate_names = flatten([
    for kind in local.known_kinds : [
      for n in distinct(local.names[kind]) : "${kind}/${n}"
      if length([for m in local.names[kind] : m if m == n]) > 1
    ]
  ])

  entry_count = length(flatten([for kind in local.known_kinds : local.names[kind]]))

  # One record per requested resource, carrying the name as written and the name AWS will actually see.
  entries = flatten([
    for kind in local.known_kinds : [
      for n in distinct(local.names[kind]) : {
        kind = kind
        name = n
        key  = "${kind}/${n}"
        full = "${local.app_name}-${n}"
      }
    ]
  ])

  # Lowercase alphanumeric with single hyphens: the intersection of the S3 bucket, RDS identifier and Secrets Manager rules.
  name_pattern = "^[a-z0-9]([a-z0-9]|-[a-z0-9])*$"
  name_caps    = { object_storage = 63, database = 63, secrets = 500, compute = 240 }

  # The app name may come from the list itself (`name:`), so it is untrusted too, and it must start with a letter because RDS identifiers do.
  app_name_ok = can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", local.app_name)) && length(local.app_name) <= 40

  invalid_names = [
    for e in local.entries : e.key
    if !can(regex(local.name_pattern, e.name)) || contains(var.reserved_names, e.name)
  ]

  oversized_names = [
    for e in local.entries : "${e.key} -> ${e.full}"
    if length(e.full) > local.name_caps[e.kind]
  ]

  # S3's reserved prefixes/suffixes and 3-char floor; the name pattern already rules out dots, double hyphens and IP-shaped names.
  invalid_bucket_names = [
    for e in local.entries : e.full
    if e.kind == "object_storage" && (
      length(e.full) < 3
      || length(regexall("^(xn--|sthree-|amzn-s3-demo-)", e.full)) > 0
      || length(regexall("(-s3alias|--ol-s3|--x-s3|--table-s3)$", e.full)) > 0
    )
  ]

  # modules/aws/database mints "<app_name>-<name>-db-credentials"; a secrets entry can collide with it.
  db_credential_names = [for n in local.names["database"] : "${n}-db-credentials"]
  colliding_secrets   = [for n in local.names["secrets"] : n if contains(local.db_credential_names, n)]

  # --- Per-entry options ---
  #
  # Every field here is posture-strengthening (a CMK, rotation, a standby) or security-neutral, so a
  # shopping list cannot weaken a module default. Weakening lives in stack variables (see variables.tf).
  entry_keys = {
    object_storage = ["name", "kms_key_arn"]
    secrets        = ["name", "kms_key_arn", "rotation_days"]
    database       = ["name", "engine", "kms_key_arn", "multi_az"]
    compute        = ["name", "kms_key_arn"]
  }

  # Module arguments a list may never carry: posture-weakening ones (the operator's, via var.demo_teardown),
  # platform-wide ones, and initial_value. Named rather than left to the unknown-key catch-all so the error
  # says *why* it is refused and where the control actually lives.
  refused_keys = {
    access_log_bucket                   = "the platform sets the audit-log destination stack-wide (var.access_log_bucket)"
    access_log_prefix                   = "the platform sets the audit-log destination stack-wide (var.access_log_bucket)"
    assign_public_ip                    = "network exposure is not a shopping-list decision"
    db_parameters                       = "the TLS/logging baseline is the module's, not the list's"
    deletion_protection                 = "posture-weakening: set var.demo_teardown on the stack"
    demo_teardown                       = "posture-weakening: set var.demo_teardown on the stack"
    disable_api_termination             = "posture-weakening: set var.demo_teardown on the stack"
    egress_cidr_blocks                  = "network exposure is not a shopping-list decision"
    environment                         = "the Environment tag follows the stack's env lane (var.environment), and env:* is a privilege claim"
    enforce_tls_resource_policy         = "TLS enforcement is not optional"
    force_destroy                       = "posture-weakening: set var.demo_teardown on the stack"
    ingress_rules                       = "network exposure is not a shopping-list decision"
    initial_value                       = "never put a secret value in a file in git — create the secret, then write the value out-of-band"
    owner                               = "one app, one owner: put `owner:` at the top level of the list, or set var.owner on the stack"
    publicly_accessible                 = "the database is private, full stop"
    recovery_window_in_days             = "posture-weakening: set var.demo_teardown on the stack"
    secret_recovery_window_days         = "posture-weakening: set var.demo_teardown on the stack"
    skip_final_snapshot                 = "posture-weakening: set var.demo_teardown on the stack"
    iam_database_authentication_enabled = "the module keeps IAM auth on so an app needs no stored password"
  }

  # Flattened to strings up front: a heterogeneous raw entry would give the tuple inconsistent element
  # types, and the sentinels below make "wrong type" fail the same regex/enum checks as "wrong value".
  entry_options = flatten([
    for kind in local.known_kinds : try([
      for i, r in local.raw[kind] : {
        kind     = kind
        key      = "${kind}/${try(tostring(r.name), "#${i}")}"
        keys     = try(keys(r), [])
        kms      = try(tostring(r.kms_key_arn), "<not a string>")
        engine   = try(tostring(r.engine), "<not a string>")
        rotation = try(tostring(r.rotation_days), "<not a number>")
        multi_az = try(tostring(r.multi_az), "<not a bool>")
      }
    ], [])
  ])

  unknown_entry_keys = flatten([
    for e in local.entry_options : [
      for k in e.keys : "${e.key}: ${k}"
      if !contains(local.entry_keys[e.kind], k) && !contains(keys(local.refused_keys), k)
    ]
  ])

  refused_key_attempts = flatten([
    for e in local.entry_options : [
      for k in e.keys : "${e.key}: ${k} — ${local.refused_keys[k]}"
      if contains(keys(local.refused_keys), k)
    ]
  ])

  # Key ARNs only. An alias ARN would encrypt fine and then 403 the app, because the identity policy the
  # modules emit names exactly this string as its Resource and an alias grants nothing on the key behind it.
  kms_arn_pattern = "^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/(mrk-[0-9a-f]{32}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$"

  # Presence, not truthiness: `kms_key_arn: ""` must be an error, never a silent fall-back to the
  # operator's default key — that would be a one-character way to opt out of the platform's CMK.
  kms_requests = [for e in local.entry_options : e if contains(e.keys, "kms_key_arn")]

  invalid_kms_arns = [
    for r in local.kms_requests : "${r.key} -> ${r.kms}"
    if !can(regex(local.kms_arn_pattern, r.kms))
  ]

  unauthorized_kms_arns = [
    for r in local.kms_requests : "${r.key} -> ${r.kms}"
    if can(regex(local.kms_arn_pattern, r.kms)) && !contains(var.allowed_kms_key_arns, r.kms)
  ]

  invalid_rotation_days = [
    for e in local.entry_options : "${e.key} -> ${e.rotation}"
    if contains(e.keys, "rotation_days") && !try(
      tonumber(e.rotation) >= 0 && tonumber(e.rotation) <= 365 && floor(tonumber(e.rotation)) == tonumber(e.rotation),
      false
    )
  ]

  invalid_multi_az = [
    for e in local.entry_options : "${e.key} -> ${e.multi_az}"
    if contains(e.keys, "multi_az") && !contains(["true", "false"], e.multi_az)
  ]

  # `engine:` used to be documented as informational, which is another way of saying silently ignored.
  invalid_engines = [
    for e in local.entry_options : "${e.key} -> ${e.engine}"
    if contains(e.keys, "engine") && e.engine != "postgres"
  ]

  # Withheld from the module calls, like the rejected names above, so the gate's message is what the team
  # reads instead of a module's own variable validation firing first on the same bad value.
  invalid_option_keys = distinct([
    for e in local.entry_options : e.key
    if length([for k in e.keys : k if !contains(local.entry_keys[e.kind], k)]) > 0
    || (contains(e.keys, "kms_key_arn") && !contains(var.allowed_kms_key_arns, e.kms))
    || (contains(e.keys, "rotation_days") && !try(tonumber(e.rotation) >= 0, false))
    || (contains(e.keys, "multi_az") && !contains(["true", "false"], e.multi_az))
    || (contains(e.keys, "engine") && e.engine != "postgres")
  ])

  # A bucket that logs to itself grows without bound and mixes the audit trail into the audited data.
  self_logging_buckets = [
    for e in local.entries : e.full
    if e.kind == "object_storage" && var.access_log_bucket != "" && e.full == var.access_log_bucket
  ]

  rejected_keys = distinct(concat(
    local.invalid_names,
    [for e in local.entries : e.key if length(e.full) > local.name_caps[e.kind]],
    [for e in local.entries : e.key if contains(local.invalid_bucket_names, e.full)],
    local.invalid_option_keys,
  ))

  # Keyed by name for stable addresses, de-duplicated, and rejected names withheld — the gate below already fails the plan, and this keeps its message from being buried under each module's own variable validation.
  by_name = {
    for kind in local.known_kinds : kind => try({
      for e in local.entries : e.name => local.raw[kind][index(local.names[kind], e.name)]
      if local.app_name_ok && e.kind == kind && !contains(local.rejected_keys, e.key)
    }, {})
  }

  object_storage = local.by_name["object_storage"]
  secrets        = local.by_name["secrets"]
  databases      = local.by_name["database"]
  compute        = local.by_name["compute"]
}

# The posture the platform imposes. var.demo_teardown is the only thing that weakens it, and it is a
# stack variable so a team cannot reach it. Both branches are spelled out because Terraform has no
# "use the module default" sentinel — the production values restate modules/aws/{object-storage,database,secrets}.
locals {
  force_destroy               = var.demo_teardown
  deletion_protection         = !var.demo_teardown
  skip_final_snapshot         = var.demo_teardown
  secret_recovery_window_days = var.demo_teardown ? 0 : 30

  # Resolved once so the module calls, the boundary check and the posture output cannot disagree.
  resolved_kms = merge([
    for kind in local.known_kinds : {
      for n, r in local.by_name[kind] : "${kind}/${n}" => try(tostring(r.kms_key_arn), var.default_kms_key_arn)
    }
  ]...)

  # modules/aws/compute deliberately emits no KMS statement (EC2 decrypts the root volume through its own
  # service grant, not the app role), so a compute-only CMK needs nothing from the app role or its boundary.
  kms_grant_kinds = ["object_storage", "secrets", "database"]

  cmks_needing_grant = distinct(compact([
    for k, arn in local.resolved_kms : arn if contains(local.kms_grant_kinds, split("/", k)[0])
  ]))
}

# Fail fast if the shopping list asks for a cloud this engine doesn't serve.
resource "terraform_data" "cloud_guard" {
  lifecycle {
    precondition {
      condition     = local.cloud == "aws"
      error_message = "This engine is the AWS path; the shopping list requests cloud '${local.cloud}'. Azure/GCP use the same modules with their own provider — see modules/${local.cloud}/ and the README."
    }
  }
}

# Structure, size and naming gate on the team-supplied list: everything here is plan-time, so a bad list never reaches apply.
resource "terraform_data" "shopping_list_guard" {
  input = local.entry_count

  lifecycle {
    precondition {
      condition     = local.spec_ok && local.resources_ok
      error_message = "The shopping list must decode to a mapping with an optional `resources:` mapping. Got: ${jsonencode(try(local.spec, null))}."
    }
    precondition {
      condition     = local.app_name_ok
      error_message = "App name '${local.app_name}' must be lowercase, start with a letter, use single hyphens, and be <= 40 chars — it prefixes every resource name and the <app_name>-app role."
    }
    # Checked here rather than left to the policy: "missing required tags: Owner" naming a bucket address is a
    # much worse first clue than a message naming the input that is absent.
    precondition {
      condition     = local.environment_ok
      error_message = "Environment tag is '${local.environment}', which is empty or malformed. Set TF_VAR_environment on the stack to its lane (dev / stage / prod — bootstrap/environments labels each app-factory stack env:<environment>). It is not a shopping-list field: policies/plan/protect-env-labels.rego treats env:* as a privilege claim. Without it policies/plan/enforce-required-tags.rego denies the run."
    }
    precondition {
      condition     = local.owner_ok
      error_message = "Owner tag is '${local.owner}', which is empty or malformed. Set `owner: <team>` at the top level of the shopping list, or TF_VAR_owner on the stack (which wins). Lowercase alphanumerics and single hyphens, <= 40 chars — the same charset as the stack's team: label. Without it policies/plan/enforce-required-tags.rego denies the run."
    }
    precondition {
      condition     = length(local.unknown_top_keys) == 0
      error_message = "Unknown top-level key(s) in the shopping list: ${join(", ", local.unknown_top_keys)}. Supported: ${join(", ", local.known_top_keys)}. The env lane (var.environment) and platform posture (var.demo_teardown, var.access_log_bucket, var.allowed_kms_key_arns) are set on the stack, not in the list."
    }
    precondition {
      condition     = length(local.unknown_kinds) == 0
      error_message = "Unknown resource kind(s) under `resources:`: ${join(", ", local.unknown_kinds)}. Supported: ${join(", ", local.known_kinds)}. (Silently ignoring these would let a typo look like a fulfilled order.)"
    }
    precondition {
      condition     = length(local.malformed_kinds) == 0
      error_message = "Resource kind(s) ${join(", ", local.malformed_kinds)} must be a list of entries, each an object with a string `name:`."
    }
    precondition {
      condition     = local.entry_count <= var.max_resources
      error_message = "Shopping list requests ${local.entry_count} resources; the cap is ${var.max_resources} (var.max_resources). Split the app or raise the cap deliberately."
    }
    precondition {
      condition     = length(local.duplicate_names) == 0
      error_message = "Duplicate resource name(s) within a kind: ${join(", ", local.duplicate_names)}. Names must be unique per kind — they key the resource addresses and the IAM policy names."
    }
    precondition {
      condition     = length(local.invalid_names) == 0
      error_message = "Invalid or reserved resource name(s): ${join(", ", local.invalid_names)}. Use lowercase alphanumerics separated by single hyphens, and avoid ${join(", ", var.reserved_names)}."
    }
    precondition {
      condition     = length(local.oversized_names) == 0
      error_message = "Composed name(s) too long for the target service: ${join(", ", local.oversized_names)}. Caps: ${jsonencode(local.name_caps)} characters including the app-name prefix."
    }
    precondition {
      condition     = length(local.invalid_bucket_names) == 0
      error_message = "Bucket name(s) rejected by S3's rules: ${join(", ", local.invalid_bucket_names)}. Buckets must be 3-63 chars and must not use AWS-reserved prefixes (xn--, sthree-, amzn-s3-demo-) or suffixes (-s3alias, --ol-s3, --x-s3, --table-s3)."
    }
    precondition {
      condition     = length(local.colliding_secrets) == 0
      error_message = "Secret name(s) ${join(", ", local.colliding_secrets)} collide with the credentials secret modules/aws/database creates for a database of the same stem. Rename the secret."
    }

    # --- Per-entry options. Same principle as the unknown-kind check: a mistyped security field must
    # fail the plan, not be dropped while the team believes the control is on. ---
    precondition {
      condition     = length(local.refused_key_attempts) == 0
      error_message = "A shopping list may not set: ${join("; ", local.refused_key_attempts)}. The posture-weakening ones are stack variables precisely because a team cannot write to the stack — weakening a default has to be an operator act with an audit trail."
    }
    precondition {
      condition     = length(local.unknown_entry_keys) == 0
      error_message = "Unknown option(s) on shopping-list entries: ${join(", ", local.unknown_entry_keys)}. Per-kind options: ${jsonencode(local.entry_keys)}."
    }
    precondition {
      condition     = length(local.invalid_kms_arns) == 0
      error_message = "Malformed kms_key_arn: ${join(", ", local.invalid_kms_arns)}. Expected a KMS *key* ARN, arn:aws:kms:<region>:<account>:key/<uuid|mrk-...>. Alias ARNs are rejected: the app role's grant names this exact string, and an alias grants nothing on the key behind it."
    }
    precondition {
      condition     = length(local.unauthorized_kms_arns) == 0
      error_message = "kms_key_arn not published by the platform: ${join(", ", local.unauthorized_kms_arns)}. Allowed: ${length(var.allowed_kms_key_arns) == 0 ? "(none — the platform has published no CMK for this stack; ask for one to be added to var.allowed_kms_key_arns)" : join(", ", var.allowed_kms_key_arns)}."
    }
    precondition {
      condition     = length(local.invalid_rotation_days) == 0
      error_message = "Invalid rotation_days: ${join(", ", local.invalid_rotation_days)}. Must be a whole number of days, 0 (no rotation) to 365."
    }
    precondition {
      condition     = length(local.invalid_multi_az) == 0
      error_message = "Invalid multi_az: ${join(", ", local.invalid_multi_az)}. Must be a boolean — true or false (yamldecode also reads yes/on/y as true). A number or a word like \"enabled\" is refused rather than guessed at."
    }
    precondition {
      condition     = length(local.invalid_engines) == 0
      error_message = "Unsupported database engine: ${join(", ", local.invalid_engines)}. modules/aws/database is PostgreSQL-only; `engine:` is checked rather than ignored so the field means something."
    }
    precondition {
      condition     = length(local.self_logging_buckets) == 0
      error_message = "Bucket(s) ${join(", ", local.self_logging_buckets)} would be their own access-log target (var.access_log_bucket). A bucket logging to itself grows without bound and mixes the audit trail into the audited data — point var.access_log_bucket at a bucket this stack does not vend."
    }
  }
}

# A permissions boundary is an INTERSECTION, so the kms:Decrypt/GenerateDataKey/DescribeKey statements the
# modules add to iam_policy_json are only effective if the boundary allows them too. Terraform cannot read
# the boundary's document without calling IAM (this stack plans without credentials, and must keep doing
# so), hence a warning rather than a gate: the runtime symptom is an AccessDenied naming the KEY, which
# sends whoever debugs it to the key policy instead of the boundary.
check "cmk_needs_boundary_kms" {
  assert {
    condition     = var.app_role_permissions_boundary_arn == "" || length(local.cmks_needing_grant) == 0
    error_message = "App role ${local.app_name}-app has permissions boundary ${var.app_role_permissions_boundary_arn} AND CMK-encrypted resources (${join(", ", local.cmks_needing_grant)}). Confirm the boundary allows kms:Decrypt, kms:GenerateDataKey and kms:DescribeKey on those keys, or every read of a CMK-encrypted bucket/secret fails at runtime with an error that points at the key rather than at the boundary."
  }
}

# Loud on every plan, because a production stack carrying this flag is a finding and silence is how it survives.
check "demo_teardown_weakens_posture" {
  assert {
    condition     = !var.demo_teardown
    error_message = "var.demo_teardown is on for ${local.app_name}: buckets are force_destroy, the database has no deletion protection and takes no final snapshot, and credential secrets have a 0-day recovery window. Correct for an ephemeral demo environment, a data-loss incident waiting to happen anywhere else."
  }
}

module "object_storage" {
  source   = "../../modules/aws/object-storage"
  for_each = local.object_storage

  name = "${local.app_name}-${each.key}"
  tags = local.tags

  kms_key_arn = local.resolved_kms["object_storage/${each.key}"]

  access_log_bucket = var.access_log_bucket
  force_destroy     = local.force_destroy

  depends_on = [terraform_data.shopping_list_guard]
}

module "secrets" {
  source   = "../../modules/aws/secrets"
  for_each = local.secrets

  name = "${local.app_name}-${each.key}"
  tags = local.tags

  kms_key_arn = local.resolved_kms["secrets/${each.key}"]
  # 0 restates the module default: no rotation unless the team asks for it.
  rotation_days = try(tonumber(each.value.rotation_days), 0)

  recovery_window_in_days = local.secret_recovery_window_days

  depends_on = [terraform_data.shopping_list_guard]
}

module "database" {
  source   = "../../modules/aws/database"
  for_each = local.databases

  name = "${local.app_name}-${each.key}"
  tags = local.tags

  kms_key_arn = local.resolved_kms["database/${each.key}"]
  # false restates the module default: a standby roughly doubles the cost, so it is opted into.
  multi_az = try(tobool(each.value.multi_az), false)

  deletion_protection         = local.deletion_protection
  skip_final_snapshot         = local.skip_final_snapshot
  secret_recovery_window_days = local.secret_recovery_window_days

  depends_on = [terraform_data.shopping_list_guard]
}

# No teardown hatch: modules/aws/compute already leaves disable_api_termination off, so a destroy works.
module "compute" {
  source   = "../../modules/aws/compute"
  for_each = local.compute

  name = "${local.app_name}-${each.key}"
  tags = local.tags

  kms_key_arn = local.resolved_kms["compute/${each.key}"]

  depends_on = [terraform_data.shopping_list_guard]
}
