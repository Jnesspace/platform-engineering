# One-time ROOT-ADMIN bootstrap: Spaces, admin-owned engine stack, Space-admin role bound to the STACK (never a user), non-admin team role.

# Resolve the system role by slug so no account-specific ULID is hardcoded.
data "spacelift_role" "space_admin" {
  slug = "space-admin"
}

locals {
  space_admin_role_id = coalesce(var.space_admin_role_id, data.spacelift_role.space_admin.id)
}

# inherit_entities=false (no root leakage) is set here because disabling inheritance is a root-admin-only operation.
resource "spacelift_space" "platform" {
  name             = var.platform_space_name
  parent_space_id  = "root"
  description      = "Governance plane. The onboarding engine and admin-owned config live here."
  inherit_entities = false
}

resource "spacelift_space" "team" {
  name             = var.team_name
  parent_space_id  = "root"
  description      = "Product team Space. Team holds a non-admin role; the engine reaches in via a scoped role binding."
  inherit_entities = false
}

# With inheritance off, downstream cloud credentials must live IN the team Space; prefer per-Space OIDC roles as in patterns/iam-factory.

# Engine stack: its power comes solely from the role binding below (no deprecated `administrative` flag).
resource "spacelift_stack" "onboarding_engine" {
  name         = var.engine_stack_name
  space_id     = spacelift_space.platform.id
  repository   = var.repository
  branch       = var.branch
  project_root = var.engine_project_root
  description  = "Admin-owned onboarding engine. Gets Space-admin on ${var.team_name} via a role binding; creates app stacks in the team Space with no deployer admin."
  labels       = ["poc:nonadmin-launcher", "engine"]

  autodeploy              = false # runs pause at the sign-off gate
  terraform_workflow_tool = "TERRAFORM_FOSS"
  terraform_version       = "1.5.7"

  # Runs carry an elevated token: mask secret shapes in logs, block accidental deletion.
  enable_well_known_secret_masking = true
  protect_from_deletion            = true
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

# No SPACE_ADMIN/STACK_UPDATE, so holders cannot edit env or attach roles.
resource "spacelift_role" "team_consumer" {
  name        = "${var.team_name}-consumer"
  description = "Non-admin product-team role: read + trigger/confirm runs. No SPACE_ADMIN, no STACK_UPDATE."
  actions     = ["SPACE_READ", "RUN_TRIGGER", "RUN_CONFIRM"]
}

# Stack-scoped (not Space-scoped) so the team can trigger ONLY this entry point; set a real subject to activate.
# resource "spacelift_role_attachment" "team_launch" {
#   role_id  = spacelift_role.team_consumer.id
#   stack_id = spacelift_stack.onboarding_engine.id
#   # idp_group_mapping_id = "<...>"   # or user_id = "<ulid>"
# }
