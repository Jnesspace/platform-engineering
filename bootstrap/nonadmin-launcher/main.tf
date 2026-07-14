##############################################################################
# Platform provisioning — the "non-admin launcher" pattern as code
#
# This is the platform team's ONE-TIME, root-admin setup. It stands up, per
# product team:
#   1. a governance Space (`platform`) and the team's Space (`cpe-team1`)
#   2. the admin-owned engine stack (runs code in ../../patterns/nonadmin-launcher/engine)
#   3. the single privileged object: a Space-admin role binding attaching that
#      role to the ENGINE STACK, scoped to the team Space
#   4. a non-admin team role (read + trigger/confirm)
#
# The elevation lives on the stack (step 3), not on any user. Product-team
# users hold only the role from step 4 and simply trigger the engine; its runs
# act with the bound role, independent of who triggered them.
#
# NOTE: creating roles and attaching Space Admin both require ROOT admin — that
# is the deliberate boundary. Apply this as a root-admin identity (see README).
##############################################################################

# Resolve the system "Space admin" role by its stable slug instead of a
# hardcoded, account-specific ULID. var.space_admin_role_id remains an
# optional escape hatch.
data "spacelift_role" "space_admin" {
  slug = "space-admin"
}

locals {
  space_admin_role_id = coalesce(var.space_admin_role_id, data.spacelift_role.space_admin.id)
}

# --- 1. Spaces -------------------------------------------------------------
# inherit_entities = false on both: these Spaces do NOT inherit parent/root
# contexts, policies, or integrations — the tighter, no-leakage default. It is
# set HERE, at creation, on purpose: disabling inheritance is a ROOT-ADMIN-only
# operation ("only root admins can disable inheritance"), and this bootstrap is
# the root-admin step. The non-root engine could never do it.
#
# Consequence: anything a stack in these Spaces needs — a non-default AWS/VCS
# integration, a shared context — must be attached DIRECTLY to that Space/stack
# by the platform admin, because nothing flows down from root and the engine
# (scoped to the team Space) cannot reach root-level integrations. The demo's
# app-example needs none, so nothing extra is required here; add per-Space
# attachments when real downstream workloads need cloud credentials.
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

# --- 2. The admin-owned engine stack ---------------------------------------
# We deliberately do NOT set `administrative` (deprecated). The engine's power
# comes solely from the role binding below.
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

  # Cheap hardening: mask well-known secret shapes in logs (the run carries an
  # elevated token) and refuse accidental deletion of the privileged stack.
  enable_well_known_secret_masking = true
  protect_from_deletion            = true
}

# Hand the engine stack the team Space id so its runs know where to provision.
resource "spacelift_environment_variable" "engine_team_space" {
  stack_id   = spacelift_stack.onboarding_engine.id
  name       = "TF_VAR_team_space_id"
  value      = spacelift_space.team.id
  write_only = false
}

# Tell the engine what the VENDED app stacks should track, so nothing about
# the vended repo/branch/path is hardcoded in the engine code.
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

# --- 3. The elevation: Space-admin role bound to the STACK, scoped to team --
resource "spacelift_role_attachment" "engine_admin_on_team" {
  stack_id = spacelift_stack.onboarding_engine.id
  role_id  = local.space_admin_role_id
  space_id = spacelift_space.team.id
}

# --- 4. The non-admin team role --------------------------------------------
# No SPACE_ADMIN and no STACK_UPDATE, so holders cannot edit env:* labels or
# attach roles. Assign it to the team's users/IdP group (example below).
resource "spacelift_role" "team_consumer" {
  name        = "${var.team_name}-consumer"
  description = "Non-admin product-team role: read + trigger/confirm runs. No SPACE_ADMIN, no STACK_UPDATE."
  actions     = ["SPACE_READ", "RUN_TRIGGER", "RUN_CONFIRM"]
}

# Give the product team trigger rights on ONLY the engine stack (not the whole
# platform Space). A Space-scoped attachment would let the team trigger every
# stack in `platform`; stack scope confines them to this one governed entry
# point. Set a real subject (idp_group_mapping_id or user_id) to activate.
# resource "spacelift_role_attachment" "team_launch" {
#   role_id  = spacelift_role.team_consumer.id
#   stack_id = spacelift_stack.onboarding_engine.id
#   # idp_group_mapping_id = "<...>"   # or user_id = "<ulid>"
# }
