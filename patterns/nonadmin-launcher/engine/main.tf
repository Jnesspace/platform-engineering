# Admin-owned onboarding engine: runs act with the Space-admin role bound to this STACK, so triggering users never hold admin. Teams submit requests/*.yaml (data, not code) — validated here, because the engine executes with elevated credentials and the requests are the one thing a non-admin controls.

terraform {
  # terraform_data (the request gate) needs >= 1.4.
  required_version = ">= 1.4"

  required_providers {
    spacelift = {
      source  = "spacelift-io/spacelift"
      version = "~> 1.0"
    }
  }
}

# Auth via the run's injected SPACELIFT_API_TOKEN, which carries this stack's role-binding permissions.
provider "spacelift" {}

# No default: a missing TF_VAR_team_space_id must fail loudly, not fall back to a stale Space.
variable "team_space_id" {
  type        = string
  description = "The product team's Space that this engine provisions into."
}

variable "vended_repository" {
  type        = string
  description = "Repository the vended app stacks track."
  default     = "platform-engineering"
}

variable "vended_branch" {
  type        = string
  description = "Branch the vended app stacks track."
  default     = "main"
}

variable "vended_project_root" {
  type        = string
  description = "Project root (directory) in the repository for the vended app stacks."
  default     = "patterns/nonadmin-launcher/engine/app-example"
}

# A request-supplied project_root would let a team point a vended stack at ANY directory in this repo — bootstrap/, iam-factory, another team's pattern — and have it run with whatever the team Space's integrations grant. The override therefore has to be an allowlist, not free text.
variable "allowed_project_roots" {
  type        = list(string)
  default     = []
  description = "Additional project roots a request may name. vended_project_root is always allowed; anything else fails the plan. Empty means requests cannot override it at all."
}

# env:* labels are the promotion lanes that policies/plan/protect-env-labels.rego guards, so the engine must stamp a real one rather than an invented "d". prod is absent deliberately: launcher-engine-guardrail.rego treats env:prod as a privilege claim an engine may not make.
variable "vended_env" {
  type        = string
  default     = "dev"
  description = "Environment label applied to vended stacks as env:<value>. dev or stage only — a prod stack is not something a self-service engine hands out."

  validation {
    condition     = contains(["dev", "stage"], var.vended_env)
    error_message = "vended_env must be dev or stage. env:prod is refused server-side by policies/plan/launcher-engine-guardrail.rego — route prod through bootstrap/environments."
  }
}

# Matches launcher_max_stacks in policies/plan/launcher-engine-guardrail.rego, so the in-code gate fails first with a message naming the file to change.
variable "max_requests" {
  type        = number
  default     = 10
  description = "Cap on requests/*.yaml processed in one run. Each mints a stack in the team Space with the engine's elevated token."

  validation {
    condition     = var.max_requests >= 1
    error_message = "max_requests must be at least 1."
  }
}

locals {
  # One requests/<slug>.yaml per app stack; filename = stack slug. Both extensions, so a .yml file isn't silently ignored.
  request_files = tolist(setunion(
    fileset("${path.module}/requests", "*.yaml"),
    fileset("${path.module}/requests", "*.yml"),
  ))
  request_slugs = [for f in local.request_files : trimsuffix(trimsuffix(f, ".yaml"), ".yml")]

  # De-duplicated so the gate's message wins over Terraform's raw "Duplicate object key".
  duplicate_slugs = [
    for s in distinct(local.request_slugs) : s
    if length([for t in local.request_slugs : t if t == s]) > 1
  ]
  app_stacks = {
    for s in distinct(local.request_slugs) :
    s => yamldecode(file("${path.module}/requests/${local.request_files[index(local.request_slugs, s)]}"))
  }

  malformed_requests = [for k, v in local.app_stacks : k if !can(keys(v))]

  # Only these keys are honoured; a request must not be able to set labels (the access/plan policies key off them) or any other stack attribute.
  allowed_keys = ["name", "project_root"]
  unknown_keys = distinct(flatten([
    for k, v in local.app_stacks : [
      for key in try(keys(v), []) : "${k}: ${key}" if !contains(local.allowed_keys, key)
    ]
  ]))

  stack_names   = { for k, v in local.app_stacks : k => try(tostring(v.name), k) }
  project_roots = { for k, v in local.app_stacks : k => try(tostring(v.project_root), "") }
  allowed_roots = distinct(concat([var.vended_project_root], var.allowed_project_roots))
  disallowed_roots = [
    for k, r in local.project_roots : "${k} -> ${r}"
    if r != "" && !contains(local.allowed_roots, r)
  ]

  labels = ["env:${var.vended_env}", "vended-by:onboarding-engine"]
}

# Plan-time gate on the whole request set: shape, volume and the project_root allowlist, before the elevated token creates anything.
resource "terraform_data" "request_gate" {
  input = length(local.app_stacks)

  lifecycle {
    precondition {
      condition     = length(local.duplicate_slugs) == 0
      error_message = "requests/ contains both .yaml and .yml for slug(s): ${join(", ", local.duplicate_slugs)}. One file per stack — the slug names the stack."
    }
    precondition {
      condition     = length(local.malformed_requests) == 0
      error_message = "requests/ file(s) ${join(", ", local.malformed_requests)} must decode to a mapping with `name:` and optionally `project_root:`."
    }
    precondition {
      condition     = length(local.unknown_keys) == 0
      error_message = "Unsupported key(s) in requests: ${join("; ", local.unknown_keys)}. Only ${join(", ", local.allowed_keys)} are honoured — labels and other stack attributes are the engine's to set, because the access and plan policies depend on them."
    }
    precondition {
      condition     = length(local.app_stacks) <= var.max_requests
      error_message = "${length(local.app_stacks)} stacks requested; the cap is ${var.max_requests} (var.max_requests)."
    }
    precondition {
      condition     = length(local.disallowed_roots) == 0
      error_message = "Request(s) name a project_root outside the allowlist: ${join(", ", local.disallowed_roots)}. Allowed: ${join(", ", local.allowed_roots)}. A vended stack runs whatever Terraform lives at that path, so the path is a privilege decision, not a request field."
    }
  }
}

resource "spacelift_stack" "app" {
  for_each = local.app_stacks

  depends_on = [terraform_data.request_gate]

  name                  = local.stack_names[each.key]
  space_id              = var.team_space_id
  repository            = var.vended_repository
  branch                = var.vended_branch
  project_root          = local.project_roots[each.key] != "" ? local.project_roots[each.key] : var.vended_project_root
  description           = "App stack '${each.key}' vended into ${var.team_space_id} by the onboarding engine."
  labels                = local.labels
  autodeploy            = false
  protect_from_deletion = true

  lifecycle {
    precondition {
      # Also the stack slug Spacelift derives, so keep it short and clean.
      condition     = can(regex("^[a-z0-9][a-z0-9-]{0,38}[a-z0-9]$", each.key))
      error_message = "App request slug '${each.key}' must be lowercase alphanumeric/hyphen, start and end alphanumeric, and be 2-40 chars."
    }
    precondition {
      # Same shape as launcher_name_pattern in policies/plan/launcher-engine-guardrail.rego: the local gate should fail before the server-side one does.
      condition     = can(regex("^[a-z0-9][a-z0-9-]{1,62}$", local.stack_names[each.key]))
      error_message = "Request '${each.key}' has an invalid `name:` ('${local.stack_names[each.key]}'). Vended stack names must be lowercase alphanumeric/hyphen, 2-63 chars, starting alphanumeric — the same shape policies/plan/launcher-engine-guardrail.rego enforces server-side."
    }
  }
}

output "vended_app_stacks" {
  value       = { for k, s in spacelift_stack.app : k => s.id }
  description = "Map of app stack name => created stack ID (proves cross-Space creation)."
}
