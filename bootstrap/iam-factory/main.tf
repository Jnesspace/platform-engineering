# One-time ROOT-ADMIN bootstrap for the iam-factory: admin-plane Space, factory stack, Space-admin
# role bound to the STACK, config + AWS integration, private worker pool.

data "spacelift_role" "space_admin" {
  slug = "space-admin"
}

# The pool is created by worker-pools/ and found by NAME, so no ULID crosses the root boundary.
data "spacelift_worker_pools" "all" {}

locals {
  space_admin_role_id = coalesce(var.space_admin_role_id, data.spacelift_role.space_admin.id)

  elevated_pools          = [for p in data.spacelift_worker_pools.all.worker_pools : p if p.name == var.elevated_worker_pool_name]
  elevated_worker_pool_id = length(local.elevated_pools) == 1 ? local.elevated_pools[0].worker_pool_id : null
}

# inherit_entities defaults to true so the factory stack can reach the root-level AWS integration,
# worker pool and policy set. See README before flipping it.
resource "spacelift_space" "platform_admin" {
  name             = var.space_name
  parent_space_id  = "root"
  description      = "Admin plane. The iam-factory stack lives here; every vended service Space is a child of it."
  inherit_entities = var.inherit_entities
}

# Factory stack: power comes from the role binding below; autodeploy off pauses runs at the sign-off gate.
resource "spacelift_stack" "factory" {
  name         = "iam-factory"
  space_id     = spacelift_space.platform_admin.id
  repository   = var.repository
  branch       = var.branch
  project_root = var.project_root
  description  = "Role + Space vending machine. Reads services/*.yaml + catalog.yaml and mints scoped, OIDC-trusted AWS roles per service."

  # `elevated` is the marker bootstrap/governance audits; the rest are for humans and autoattach.
  labels = ["platform-factory", "elevated"]

  autodeploy              = false
  terraform_workflow_tool = "TERRAFORM_FOSS"
  terraform_version       = "1.5.7"
  protect_from_deletion   = true

  # Runs carry an elevated token: keep it off shared workers and mask secret shapes in logs.
  worker_pool_id                   = local.elevated_worker_pool_id
  enable_well_known_secret_masking = true

  lifecycle {
    precondition {
      condition     = local.elevated_worker_pool_id != null
      error_message = "Expected exactly one worker pool named '${var.elevated_worker_pool_name}', found ${length(local.elevated_pools)}. Apply worker-pools/ first — an elevated token must not fall back to shared workers."
    }
  }
}

# The elevation: Space-admin bound to the STACK, scoped to the admin plane.
resource "spacelift_role_attachment" "factory_admin" {
  stack_id = spacelift_stack.factory.id
  role_id  = local.space_admin_role_id
  space_id = spacelift_space.platform_admin.id
}

resource "spacelift_environment_variable" "parent_space" {
  stack_id   = spacelift_stack.factory.id
  name       = "TF_VAR_parent_space_id"
  value      = spacelift_space.platform_admin.id
  write_only = false
}

resource "spacelift_environment_variable" "subdomain" {
  stack_id   = spacelift_stack.factory.id
  name       = "TF_VAR_account_subdomain"
  value      = var.account_subdomain
  write_only = false
}

resource "spacelift_environment_variable" "create_oidc" {
  stack_id   = spacelift_stack.factory.id
  name       = "TF_VAR_create_oidc_provider"
  value      = tostring(var.create_oidc_provider)
  write_only = false
}

resource "spacelift_environment_variable" "factory_region" {
  stack_id   = spacelift_stack.factory.id
  name       = "AWS_DEFAULT_REGION"
  value      = var.aws_region
  write_only = false
}

# AWS integration so factory runs can mint IAM roles.
resource "spacelift_aws_integration_attachment" "factory" {
  integration_id = var.aws_integration_id
  stack_id       = spacelift_stack.factory.id
  read           = true
  write          = true
}
