# Admin-owned onboarding engine: runs act with the Space-admin role bound to this STACK, so triggering users never hold admin. Teams submit requests/*.yaml (data, not code).

terraform {
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

locals {
  # One requests/<slug>.yaml per app stack; filename = stack slug.
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
