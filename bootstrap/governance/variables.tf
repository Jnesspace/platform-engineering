# No account-specific defaults anywhere: this root is applied against whatever account holds the root-admin key.

# A policy is only usable by stacks in its own Space or in Spaces that inherit entities from it.
# So: list the account root PLUS every Space that holds governed stacks and does NOT inherit
# (e.g. the team Space in bootstrap/nonadmin-launcher). Listing a Space that already inherits
# from a listed Space duplicates NOTIFICATION policies and double-fires them.
variable "policy_spaces" {
  type        = set(string)
  description = "Spaces to publish the policy set into. Root plus every inheritance-isolated Space holding governed stacks."

  validation {
    condition     = length(var.policy_spaces) > 0
    error_message = "policy_spaces must list at least one Space (normally \"root\")."
  }

  validation {
    condition     = alltrue([for s in var.policy_spaces : can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$", s))])
    error_message = "Each policy_spaces entry must be a Space ID (slug): alphanumerics and hyphens, e.g. \"root\" or \"cpe-team1-01H8...\"."
  }
}

# Overrides the per-type coverage matrix in policies.tf. Keys are Spacelift policy types.
variable "autoattach_targets" {
  type        = map(list(string))
  default     = {}
  description = "Per-policy-type override of the autoattach targets. \"*\" means every stack and module in the policy's Space subtree."

  validation {
    condition = alltrue([
      for t in keys(var.autoattach_targets) :
      contains(["ACCESS", "APPROVAL", "GIT_PUSH", "INITIALIZATION", "INTENT", "LOGIN", "NOTIFICATION", "PLAN", "TASK", "TRIGGER"], t)
    ])
    error_message = "autoattach_targets keys must be Spacelift policy types (ACCESS, APPROVAL, GIT_PUSH, INITIALIZATION, INTENT, LOGIN, NOTIFICATION, PLAN, TASK, TRIGGER)."
  }

  # Mirrors local.retired_types in policies.tf, which a variable validation cannot reference.
  # Without this, targeting a retired type is accepted and does nothing at all.
  validation {
    condition = length(setintersection(
      toset(keys(var.autoattach_targets)),
      toset(["ACCESS", "INITIALIZATION", "TASK"]),
    )) == 0
    error_message = "ACCESS, INITIALIZATION and TASK policies were removed by Spacelift on 2026-05-30 and are never published by this root, so an autoattach target for them would silently do nothing. Remove the key."
  }
}

# Escape hatch for one policy that must not follow its type's default (e.g. an APPROVAL policy
# that should only cover env:prod). Keyed "<dir>/<name>" — a rename in policies/ makes the key
# stop resolving and the discovery gate fails loudly rather than dropping the override silently.
variable "policy_target_overrides" {
  type        = map(list(string))
  default     = {}
  description = "Per-policy autoattach override, keyed \"<policy dir>/<policy file name without .rego>\"."
}

# Values that used to be hardcoded inside the .rego files. Rego takes no Terraform variables, so
# policies/ ships a placeholder and policies.tf substitutes these at publish time. No defaults for
# the two that back an ENFORCING policy: there is no safe generic value, and the discovery gate
# fails the plan rather than publishing a placeholder.
variable "repo_owner" {
  type        = string
  description = "Owner (org or user) of the canonical repository, for push/ignore-untrusted-authors.rego. Spacelift's stack.namespace is documented as GitLab-only, so it cannot be derived from the run."

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9-]{0,38}$", var.repo_owner))
    error_message = "repo_owner must be a VCS account name: alphanumerics and hyphens, starting alphanumeric, at most 39 characters."
  }
}

variable "trusted_pr_authors" {
  type        = list(string)
  description = "VCS logins whose pull requests may produce a proposed run. Compared case-insensitively; lowercased at publish time."

  validation {
    condition     = length(var.trusted_pr_authors) > 0
    error_message = "trusted_pr_authors must list at least one login. An empty list publishes a policy that ignores every pull request in the account."
  }

  validation {
    condition     = alltrue([for a in var.trusted_pr_authors : can(regex("^[A-Za-z0-9][A-Za-z0-9-]{0,38}$", a))])
    error_message = "Each trusted_pr_authors entry must be a VCS login: alphanumerics and hyphens, starting alphanumeric, at most 39 characters."
  }
}

# Defaulted, because this one backs a ROUTING policy rather than a gate: unset means the Slack
# policy is not published at all (see local.skipped), which is honest. Publishing it with an empty
# channel would drop every message silently — the exact failure the placeholder replaced.
variable "slack_channel_id" {
  type        = string
  default     = ""
  description = "Slack channel ID for notification/notify-failed-runs.rego, e.g. C0123456789. Empty means the NOTIFICATION policy is not published."

  validation {
    condition     = var.slack_channel_id == "" || can(regex("^[CG][A-Z0-9]{8,}$", var.slack_channel_id))
    error_message = "slack_channel_id must be a Slack channel ID (C or G followed by at least 8 uppercase alphanumerics), not a channel name. A wrong ID fails silently, so the shape is checked here."
  }
}

# The label every elevated stack must carry. bootstrap/* sets it; the audit in audit.tf reads it.
variable "elevated_stack_label" {
  type        = string
  default     = "elevated"
  description = "Label marking a stack as running with elevated credentials."

  validation {
    condition     = length(trimspace(var.elevated_stack_label)) > 0
    error_message = "elevated_stack_label must not be empty."
  }
}

# Turning this off means an elevated stack can quietly land on shared workers or outside policy reach.
variable "enforce_elevated_stack_audit" {
  type        = bool
  default     = true
  description = "Fail the plan when a stack labelled elevated_stack_label escapes the guardrails."
}
