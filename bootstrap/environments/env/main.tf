# One environment's plane: a platform-<env> Space + an app-factory stack tracking the env's branch.

locals {
  # Env in the app name so bucket/secret names differ per env — collision-safe on one shared account.
  shopping_list_yaml = yamlencode({
    name  = "demo-${var.environment}"
    cloud = "aws"
    resources = {
      object_storage = [{ name = "uploads" }]
      secrets        = [{ name = "app-secrets" }]
    }
  })
}

# inherit_entities=true so the stack can reach the root-level AWS integration, the private worker
# pool, and the governance policy set published in root.
resource "spacelift_space" "env" {
  name             = "platform-${var.environment}"
  parent_space_id  = var.parent_space
  description      = "The ${var.environment} platform plane; its stacks track the '${var.branch}' branch."
  inherit_entities = true
}

resource "spacelift_stack" "app_factory" {
  name         = "app-factory-${var.environment}"
  space_id     = spacelift_space.env.id
  repository   = var.repository
  branch       = var.branch
  project_root = "patterns/app-factory"
  description  = "app-factory for ${var.environment}: merges to '${var.branch}' trigger this stack."

  # `elevated` is the marker bootstrap/governance audits: this stack mints IAM roles.
  labels = ["env:${var.environment}", "app-factory", "elevated"]

  autodeploy              = var.autodeploy
  terraform_workflow_tool = "TERRAFORM_FOSS"
  terraform_version       = "1.5.7"

  # Elevated credentials: private pool, masked logs, no accidental teardown of a whole env plane.
  worker_pool_id                   = var.worker_pool_id
  enable_well_known_secret_masking = true
  protect_from_deletion            = true
}

resource "spacelift_aws_integration_attachment" "env" {
  integration_id = var.aws_integration_id
  stack_id       = spacelift_stack.app_factory.id
  read           = true
  write          = true
}

resource "spacelift_environment_variable" "shopping_list" {
  stack_id   = spacelift_stack.app_factory.id
  name       = "TF_VAR_shopping_list_yaml"
  value      = local.shopping_list_yaml
  write_only = false
}

resource "spacelift_environment_variable" "region" {
  stack_id   = spacelift_stack.app_factory.id
  name       = "TF_VAR_region"
  value      = var.region
  write_only = false
}

resource "spacelift_environment_variable" "aws_region" {
  stack_id   = spacelift_stack.app_factory.id
  name       = "AWS_DEFAULT_REGION"
  value      = var.region
  write_only = false
}

# Environment and Owner are two of the three tags policies/plan/enforce-required-tags.rego requires
# (app-factory derives Project from the app name). Both are operator-set on the stack: a shopping
# list naming its own env would be claiming the privilege protect-env-labels.rego guards.
resource "spacelift_environment_variable" "environment" {
  stack_id   = spacelift_stack.app_factory.id
  name       = "TF_VAR_environment"
  value      = var.environment
  write_only = false
}

resource "spacelift_environment_variable" "owner" {
  stack_id   = spacelift_stack.app_factory.id
  name       = "TF_VAR_owner"
  value      = var.owner
  write_only = false
}

# Only set where it is true, so a stage/prod stack has no such variable at all rather than one
# reading "false" that a single edit could flip.
resource "spacelift_environment_variable" "demo_teardown" {
  count = var.demo_teardown ? 1 : 0

  stack_id   = spacelift_stack.app_factory.id
  name       = "TF_VAR_demo_teardown"
  value      = "true"
  write_only = false
}
