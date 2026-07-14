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
# The "shopping list" is currently a plain `list(string)` variable
# (var.app_stacks) fed in by the bootstrap — honest limitation of the PoC. A
# git-tracked YAML shopping list (like iam-factory's services/) is the
# documented next step; either way teams supply DATA only, never code.
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

# The "shopping list" — normally sourced from the team's App repo declaration.
variable "app_stacks" {
  type        = list(string)
  description = "App stacks to vend into the team Space."
  default     = ["app-stack-1", "app-stack-2"]

  validation {
    condition     = alltrue([for s in var.app_stacks : can(regex("^[a-z0-9-]+$", s))])
    error_message = "app_stacks names must be lowercase alphanumeric/hyphen."
  }
}

resource "spacelift_stack" "app" {
  for_each = toset(var.app_stacks)

  name                  = each.value
  space_id              = var.team_space_id
  repository            = var.vended_repository
  branch                = var.vended_branch
  project_root          = var.vended_project_root
  description           = "App stack vended into ${var.team_space_id} by the onboarding engine."
  labels                = ["env:d", "vended-by:onboarding-engine"]
  autodeploy            = false
  protect_from_deletion = true
}

output "vended_app_stacks" {
  value       = { for k, s in spacelift_stack.app : k => s.id }
  description = "Map of app stack name => created stack ID (proves cross-Space creation)."
}
