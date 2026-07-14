##############################################################################
# One-time admin bootstrap for the iam-factory (role + Space vending machine).
#
# Applied by an ADMIN identity (root-admin Spacelift API key, or a root admin
# stack). Creates, in Spacelift only (the factory's own runs create the AWS
# resources):
#   1. the `platform-admin` Space (parent of every vended Space)
#   2. the `iam-factory` stack tracking patterns/iam-factory/ on this repo
#   3. the elevation: Space-admin role bound to the stack, scoped to platform-admin
#   4. the stack's TF vars + region + the AWS integration attachment
#
# NOTE: like the non-admin launcher, the privileged setup here is done by an
# admin ONCE. Developers never run this — they only add a services/<slug>.yaml
# request and trigger the factory. See ../../patterns/nonadmin-launcher/README.md
# for why the deploying user cannot be the one to create the elevation.
##############################################################################

terraform {
  required_providers {
    spacelift = {
      source  = "spacelift-io/spacelift"
      version = "~> 1.0"
    }
  }
}

# Auth via SPACELIFT_API_KEY_ENDPOINT / _ID / _SECRET (a root-admin key).
provider "spacelift" {}

variable "repository" {
  type        = string
  default     = "platform-engineering"
  description = "Repository backing the factory stack (default GitHub App integration)."
}

variable "branch" {
  type        = string
  default     = "main"
  description = "Tracked branch for the factory stack."
}

variable "project_root" {
  type        = string
  default     = "patterns/iam-factory"
  description = "Directory in the repo holding the factory code."
}

variable "account_subdomain" {
  type        = string
  default     = "jnesspace"
  description = "Spacelift account subdomain; the factory's OIDC issuer/audience."
}

variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "Region for the factory's AWS provider (IAM is global; the provider still needs one)."
}

variable "aws_integration_id" {
  type        = string
  default     = "01JV4YKENC7KXV3MNBYPSH88AX" # `jakespace` -> acct 025897764856 (trust configured)
  description = "AWS integration the factory runs on. The `two` integration (025897764844) is unusable: its role trust isn't configured."
}

variable "space_admin_role_id" {
  type        = string
  default     = null
  description = "Optional override; if null, resolved from the system 'space-admin' role."
}

data "spacelift_role" "space_admin" {
  slug = "space-admin"
}

locals {
  space_admin_role_id = coalesce(var.space_admin_role_id, data.spacelift_role.space_admin.id)
}

# 1. The admin plane. inherit_entities=true so the factory stack can see the
#    root-level AWS integration (jakespace).
resource "spacelift_space" "platform_admin" {
  name             = "platform-admin"
  parent_space_id  = "root"
  description      = "Admin plane. The iam-factory stack lives here; every vended service Space is a child of it."
  inherit_entities = true
}

# 2. The factory stack. Not administrative (flag removed); power comes from the
#    role binding below. autodeploy off so runs pause at the sign-off gate.
resource "spacelift_stack" "factory" {
  name         = "iam-factory"
  space_id     = spacelift_space.platform_admin.id
  repository   = var.repository
  branch       = var.branch
  project_root = var.project_root
  description  = "Role + Space vending machine. Reads services/*.yaml + catalog.yaml and mints scoped, OIDC-trusted AWS roles per service."
  labels       = ["platform-factory"]

  autodeploy              = false
  terraform_workflow_tool = "TERRAFORM_FOSS"
  terraform_version       = "1.5.7"
  protect_from_deletion   = true
}

# 3. The elevation: Space-admin bound to the STACK, scoped to platform-admin.
resource "spacelift_role_attachment" "factory_admin" {
  stack_id = spacelift_stack.factory.id
  role_id  = local.space_admin_role_id
  space_id = spacelift_space.platform_admin.id
}

# 4. Stack config.
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
  value      = "true" # flip to false if the OIDC provider already exists in the AWS account
  write_only = false
}

resource "spacelift_environment_variable" "factory_region" {
  stack_id   = spacelift_stack.factory.id
  name       = "AWS_DEFAULT_REGION"
  value      = var.aws_region
  write_only = false
}

# 5. Attach the AWS integration so factory runs can mint IAM roles.
resource "spacelift_aws_integration_attachment" "factory" {
  integration_id = var.aws_integration_id
  stack_id       = spacelift_stack.factory.id
  read           = true
  write          = true
}

output "platform_admin_space_id" {
  value = spacelift_space.platform_admin.id
}

output "factory_stack_id" {
  value = spacelift_stack.factory.id
}
