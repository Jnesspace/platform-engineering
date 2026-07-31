# The policy delivery plane: turns every policies/<type>/<name>.rego into a live, attached Spacelift
# policy. Discovery is filesystem-driven, so adding a .rego to the right directory is the whole
# procedure — no filename list to keep in sync.

locals {
  policies_dir = "${path.module}/../../policies"

  # The DIRECTORY NAME is the Spacelift policy type. Verified against the provider schema:
  # ACCESS, APPROVAL, GIT_PUSH, INITIALIZATION, INTENT, LOGIN, PLAN, TASK, TRIGGER, NOTIFICATION.
  type_by_dir = {
    access         = "ACCESS"
    approval       = "APPROVAL"
    initialization = "INITIALIZATION"
    intent         = "INTENT"
    login          = "LOGIN"
    notification   = "NOTIFICATION"
    plan           = "PLAN"
    push           = "GIT_PUSH"
    task           = "TASK"
    trigger        = "TRIGGER"
  }

  # RETIRED TYPES. Spacelift removed stack access, task and initialization policies on 2026-05-30
  # ("Removing Legacy Policy Types": "Now: Creation of new stack access, task, and initialization
  # policies is disabled." — and the access policy docs carry "Access policies are deprecated and
  # will be entirely disabled on May 30, 2026"). The provider still accepts all three as `type`
  # strings, so nothing fails locally; the API is what rejects them, at apply time, against a live
  # account. Publishing is therefore skipped rather than attempted.
  #
  # The docs are internally inconsistent — the deprecated-policies page still shows "to be
  # announced" for task and initialization while the announcement names the same date for all
  # three. Skipping all three is the safe reading either way: no policy in this library uses those
  # types today, so the only effect is a clear message if someone adds one.
  retired_types = {
    ACCESS         = "removed 2026-05-30; use Space access control (the live equivalent here is the `roles` rule in login/map-idp-groups.rego)"
    INITIALIZATION = "removed 2026-05-30; use an APPROVAL policy"
    TASK           = "removed 2026-05-30; use an APPROVAL policy"
  }

  # THE COVERAGE MATRIX: policy type -> stack labels the policy auto-attaches to.
  # "*" is Spacelift's autoattach wildcard: every stack and module in the policy's Space subtree.
  # A guardrail you have to opt into is not a guardrail, so the enforcing types default to "*".
  # The retired types above are absent on purpose: there is nothing to attach.
  default_autoattach = {
    APPROVAL = ["*"]
    GIT_PUSH = ["*"]
    INTENT   = ["*"]
    PLAN     = ["*"]
    TRIGGER  = ["*"]

    # Neither of these is attached to stacks: LOGIN is account-global, NOTIFICATION is evaluated
    # per Space. For both, existing in the right Space IS the wiring.
    LOGIN        = []
    NOTIFICATION = []
  }

  autoattach_by_type = merge(local.default_autoattach, var.autoattach_targets)

  # policies/<dir>/<name>.rego, keyed "<dir>/<name>".
  rego_files = fileset(local.policies_dir, "*/*.rego")

  raw_bodies = { for f in local.rego_files : trimsuffix(f, ".rego") => file("${local.policies_dir}/${f}") }

  # ACCOUNT-SPECIFIC VALUES DO NOT LIVE IN REGO. Each .rego ships a placeholder shaped like the
  # value that replaces it, so the file stays ordinary standalone Rego that `opa test policies/`
  # parses and runs — and so an unsubstituted copy fails closed rather than looking configured.
  #
  # replace(), not templatefile(): a ${...} placeholder would turn every future `${` anywhere in
  # any policy into an apply-time template error, and sprintf-heavy Rego is exactly where someone
  # writes one by accident.
  trusted_authors_literal = join(", ", [for a in var.trusted_pr_authors : jsonencode(lower(a))])

  bodies = {
    for k, b in local.raw_bodies : k => replace(replace(replace(
      b,
      "\"replace-with-trusted-authors\"", local.trusted_authors_literal),
      "replace-with-repo-owner", lower(var.repo_owner)),
    "REPLACE_WITH_SLACK_CHANNEL_ID", var.slack_channel_id)
  }

  discovered = {
    for f in local.rego_files : trimsuffix(f, ".rego") => {
      dir  = dirname(f)
      slug = basename(trimsuffix(f, ".rego"))
      type = lookup(local.type_by_dir, dirname(f), null)
      body = local.bodies[trimsuffix(f, ".rego")]
    }
  }

  unmapped = { for k, p in local.discovered : k => p.dir if p.type == null }

  # Deliberately not published, with the reason kept as data so the policy does not merely vanish
  # from the output. Both cases are "publishing this would be worse than not publishing it".
  skipped = merge(
    {
      for k, p in local.discovered : k => "policy type ${p.type} ${lookup(local.retired_types, p.type, "")}"
      if p.type != null && contains(keys(local.retired_types), p.type)
    },
    {
      for k, p in local.discovered : k => "var.slack_channel_id is unset; a NOTIFICATION policy routing to an empty channel drops every message silently, which is the failure this root exists to prevent"
      if p.type == "NOTIFICATION" && var.slack_channel_id == ""
    },
  )

  publishable = { for k, p in local.discovered : k => p if p.type != null && !contains(keys(local.skipped), k) }

  # A placeholder that survives into a published body is a policy that looks configured and is not.
  unsubstituted = {
    for k, p in local.publishable : k => p.dir
    if strcontains(p.body, "replace-with-") || strcontains(p.body, "REPLACE_WITH_")
  }

  # Rego v1 syntax published as a v0 policy parses server-side but never evaluates, which is a
  # guardrail that silently does nothing. `import rego.v1` is the marker the whole library uses.
  mislabelled_engine = {
    for k, p in local.discovered : k => p.dir
    if p.type != null && !strcontains(p.body, "import rego.v1") && strcontains(p.body, " if {")
  }

  targets_by_policy = {
    for k, p in local.discovered : k => toset(
      lookup(var.policy_target_overrides, k, p.type == null ? [] : lookup(local.autoattach_by_type, p.type, []))
    )
  }

  # LOGIN is account-global: exactly one copy, in the account root. More than one login policy
  # means more than one source of truth for every session.
  login_space   = "root"
  target_spaces = setunion(var.policy_spaces, [local.login_space])

  # One publication per (Space, policy). Unmapped directories are excluded here so the discovery
  # gate below is the single, readable error.
  publications = merge([
    for s in local.target_spaces : {
      for k, p in local.publishable : "${s}/${k}" => merge(p, { key = k, space = s })
      if p.type == "LOGIN" ? s == local.login_space : contains(tolist(var.policy_spaces), s)
    }
  ]...)
}

# Plan-time discovery gate. Needs no credentials, so a bad policies/ layout fails before anything
# is published (same idiom as patterns/iam-factory's catalog gate).
resource "terraform_data" "discovery_gate" {
  input = { for k, p in local.discovered : k => p.type }

  lifecycle {
    precondition {
      condition     = length(local.unmapped) == 0
      error_message = "No Spacelift policy type for policies/${join(", ", distinct(values(local.unmapped)))}/. Move the .rego into one of: ${join(", ", keys(local.type_by_dir))}, or add the directory to local.type_by_dir."
    }

    precondition {
      condition     = length(local.mislabelled_engine) == 0
      error_message = "Rego v1 syntax without `import rego.v1`: ${join(", ", keys(local.mislabelled_engine))}. Add the import (it is what selects the REGO_V1 engine) or rewrite the rule in v0 syntax."
    }

    precondition {
      condition     = length(setsubtract(keys(var.policy_target_overrides), keys(local.discovered))) == 0
      error_message = "policy_target_overrides names policies that do not exist: ${join(", ", setsubtract(keys(var.policy_target_overrides), keys(local.discovered)))}. Keys are \"<dir>/<name>\" without .rego — check for a renamed file."
    }

    # Fails at plan time, with no credentials, rather than shipping a guardrail that reads as
    # configured and silently matches nothing.
    precondition {
      condition     = length(local.unsubstituted) == 0
      error_message = "Unsubstituted placeholder left in ${join(", ", keys(local.unsubstituted))}. A policy carrying `replace-with-*` or `REPLACE_WITH_*` must have its value wired into local.bodies in policies.tf and backed by a variable — see var.repo_owner / var.trusted_pr_authors / var.slack_channel_id."
    }

    # Spacelift OR-combines APPROVAL evaluations on a stack, so two attached approval policies
    # each weaken the other — self-approval on non-prod and single-approver prod both slipped
    # through exactly that composition before the policies were merged. One attached APPROVAL
    # policy per account, kept true here rather than by convention. An approval policy with no
    # attachments (staged via policy_target_overrides = []) does not count.
    precondition {
      condition = length([
        for k, p in local.publishable : k
        if p.type == "APPROVAL" && length(local.targets_by_policy[k]) > 0
      ]) <= 1
      error_message = "More than one attached APPROVAL policy discovered. Spacelift ORs their approve results, so the weaker one governs; keep a single approval policy (policies/approval/require-approval.rego) or detach the others via var.policy_target_overrides."
    }
  }
}

resource "spacelift_policy" "governed" {
  for_each = local.publications

  # Space-qualified so the same .rego published into two Spaces stays unique account-wide.
  name        = "${each.value.slug}@${each.value.space}"
  type        = each.value.type
  space_id    = each.value.space
  body        = each.value.body
  engine_type = strcontains(each.value.body, "import rego.v1") ? "REGO_V1" : "REGO_V0"
  description = "Managed by bootstrap/governance from policies/${each.value.dir}/${each.value.slug}.rego. Edit the .rego, not this policy."

  labels = setunion(
    [for l in local.targets_by_policy[each.value.key] : "autoattach:${l}"],
    ["managed-by:bootstrap-governance"],
  )
}
