# One-time ROOT-ADMIN bootstrap: Spaces, admin-owned engine stack, Space-admin role bound to the STACK (never a user).

# Resolve the system role by slug so no account-specific ULID is hardcoded.
data "spacelift_role" "space_admin" {
  slug = "space-admin"
}

# The pool is created by worker-pools/ and found by NAME, so no ULID crosses the root boundary.
data "spacelift_worker_pools" "all" {}

locals {
  space_admin_role_id = coalesce(var.space_admin_role_id, data.spacelift_role.space_admin.id)

  elevated_pools          = [for p in data.spacelift_worker_pools.all.worker_pools : p if p.name == var.elevated_worker_pool_name]
  elevated_worker_pool_id = length(local.elevated_pools) == 1 ? local.elevated_pools[0].worker_pool_id : null
  elevated_pool_space     = length(local.elevated_pools) == 1 ? local.elevated_pools[0].space_id : null
}

# Governance plane. Inherits root entities by default because the private worker pool and the
# governance policy set live in root, and inheritance is the only way in — see README.
resource "spacelift_space" "platform" {
  name             = var.platform_space_name
  parent_space_id  = "root"
  description      = "Governance plane. The onboarding engine and admin-owned config live here."
  inherit_entities = var.platform_space_inherit_entities
}

# Team plane, isolated: no root leakage into the Space where team-authored code runs. Disabling
# inheritance is a root-admin-only operation, which is why it happens here and not in the engine.
resource "spacelift_space" "team" {
  name             = var.team_name
  parent_space_id  = "root"
  description      = "Product team Space. Team holds a non-admin role; the engine reaches in via a scoped role binding."
  inherit_entities = var.team_space_inherit_entities
}

# With inheritance off, downstream cloud credentials must live IN the team Space; prefer per-Space
# OIDC roles as in patterns/iam-factory. Governance reaches it via bootstrap/governance policy_spaces.

# Engine stack: its power comes solely from the role binding below (no deprecated `administrative` flag).
resource "spacelift_stack" "onboarding_engine" {
  name         = var.engine_stack_name
  space_id     = spacelift_space.platform.id
  repository   = var.repository
  branch       = var.branch
  project_root = var.engine_project_root
  description  = "Admin-owned onboarding engine. Gets Space-admin on ${var.team_name} via a role binding; creates app stacks in the team Space with no deployer admin."

  # `elevated` is the marker bootstrap/governance audits; the rest are for humans and autoattach.
  labels = ["poc:nonadmin-launcher", "engine", "elevated"]

  autodeploy              = false # runs pause at the sign-off gate
  terraform_workflow_tool = "TERRAFORM_FOSS"
  terraform_version       = "1.5.7"

  # Runs carry an elevated token: keep it off shared workers, mask secret shapes, block deletion.
  worker_pool_id                   = local.elevated_worker_pool_id
  enable_well_known_secret_masking = true
  protect_from_deletion            = true

  lifecycle {
    precondition {
      condition     = local.elevated_worker_pool_id != null
      error_message = "Expected exactly one worker pool named '${var.elevated_worker_pool_name}', found ${length(local.elevated_pools)}. Apply worker-pools/ first — an elevated token must not fall back to shared workers."
    }

    precondition {
      # A pool in root is invisible to a Space that does not inherit, so the stack would never run.
      condition     = var.platform_space_inherit_entities || local.elevated_pool_space == spacelift_space.platform.id
      error_message = "Worker pool '${var.elevated_worker_pool_name}' lives in Space '${local.elevated_pool_space}' but ${var.platform_space_name} does not inherit entities, so the engine cannot see it. Set platform_space_inherit_entities = true, or apply worker-pools/ with space_id = the platform Space."
    }
  }
}

resource "spacelift_environment_variable" "engine_team_space" {
  stack_id   = spacelift_stack.onboarding_engine.id
  name       = "TF_VAR_team_space_id"
  value      = spacelift_space.team.id
  write_only = false
}

# Vended-stack repo/branch/path config, so nothing is hardcoded in the engine code.
resource "spacelift_environment_variable" "engine_vended_repository" {
  stack_id   = spacelift_stack.onboarding_engine.id
  name       = "TF_VAR_vended_repository"
  value      = var.repository
  write_only = false
}

resource "spacelift_environment_variable" "engine_vended_branch" {
  stack_id   = spacelift_stack.onboarding_engine.id
  name       = "TF_VAR_vended_branch"
  value      = var.branch
  write_only = false
}

resource "spacelift_environment_variable" "engine_vended_project_root" {
  stack_id   = spacelift_stack.onboarding_engine.id
  name       = "TF_VAR_vended_project_root"
  value      = "${var.engine_project_root}/app-example"
  write_only = false
}

# The elevation: Space-admin bound to the STACK, scoped to the team Space.
resource "spacelift_role_attachment" "engine_admin_on_team" {
  stack_id = spacelift_stack.onboarding_engine.id
  role_id  = local.space_admin_role_id
  space_id = spacelift_space.team.id
}

# The team's role is NOT defined here any more. The combined trigger+confirm role this root used to
# create was self-approvable (hardening item 2); roles/ owns the requester/approver split, binds it,
# and fails the plan if one group holds both halves. Feed it the Space IDs this root outputs.
