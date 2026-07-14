##############################################################################
# Onboarding engine (admin-owned "common engine")
#
# PoC for the "non-admin launcher" pattern. This stack lives in the `platform`
# Space and is granted Space Admin on a product team's Space via a STACK ROLE
# BINDING (the supported replacement for the deprecated `administrative` flag).
#
# Its runs receive an injected, short-lived Spacelift token carrying exactly
# that team-Space-scoped admin permission — so it can create stacks INSIDE the
# team Space without the person/identity who triggers the run holding any admin.
# Teams only ever supply inputs and trigger runs (RUN_TRIGGER); they never edit
# this admin-owned code and never hold Space Admin.
#
# The "shopping list" is git-tracked YAML: one file per app stack under
# requests/. Teams add a file and open a PR — DATA only, never code. The
# filename (minus .yaml) is the stack slug.
##############################################################################

terraform {
  required_providers {
    spacelift = {
      source  = "spacelift-io/spacelift"
      version = "~> 1.0"
    }
  }
}

# Authenticates with the run's injected SPACELIFT_API_TOKEN — which carries the
# Space-admin-on-<team> permission from this stack's role binding. No key.
provider "spacelift" {}

# Required — no default, so a missing TF_VAR_team_space_id fails loudly instead
# of silently provisioning into a stale hardcoded Space.
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

locals {
  # Git-tracked shopping list: one YAML file per requested app stack, under
  # requests/. The filename (minus .yaml) is the stack slug.
  request_files = fileset("${path.module}/requests", "*.yaml")
  app_stacks = {
    for f in local.request_files :
    trimsuffix(f, ".yaml") => yamldecode(file("${path.module}/requests/${f}"))
  }
}

resource "spacelift_stack" "app" {
  for_each = local.app_stacks

  name                  = try(each.value.name, each.key)
  space_id              = var.team_space_id
  repository            = var.vended_repository
  branch                = var.vended_branch
  project_root          = try(each.value.project_root, var.vended_project_root)
  description           = "App stack '${each.key}' vended into ${var.team_space_id} by the onboarding engine."
  labels                = ["env:d", "vended-by:onboarding-engine"]
  autodeploy            = false
  protect_from_deletion = true

  lifecycle {
    precondition {
      condition     = can(regex("^[a-z0-9-]+$", each.key))
      error_message = "App request slug '${each.key}' must be lowercase alphanumeric/hyphen."
    }
  }
}

output "vended_app_stacks" {
  value       = { for k, s in spacelift_stack.app : k => s.id }
  description = "Map of app stack name => created stack ID (proves cross-Space creation)."
}
