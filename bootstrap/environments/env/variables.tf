# All required: this module is only ever called by ../main.tf, which validates the account-specific
# values once. A default here would be a second, silent source of truth.

variable "environment" {
  type        = string
  description = "Environment name (dev/stage/prod); baked into Space, stack, and app names."
}

variable "branch" {
  type        = string
  description = "Git branch this environment's stack tracks (the promotion lane)."
}

variable "aws_integration_id" {
  type        = string
  description = "AWS integration for this env — one per env account; shared only on a demo account."
}

variable "region" {
  type        = string
  description = "AWS region for the env's vended resources."
}

variable "parent_space" {
  type        = string
  description = "Parent Space for the env Space."
}

variable "repository" {
  type        = string
  description = "Repository backing the env's stacks (name only, via the default VCS integration)."
}

variable "autodeploy" {
  type        = bool
  description = "true = merges apply unattended (dev); false = runs pause at the confirm gate (stage/prod)."
}

# app-factory mints IAM roles with a write-enabled integration, so it runs on the private pool.
variable "worker_pool_id" {
  type        = string
  description = "Private worker pool for elevated stacks; resolved by name in the calling root."
}

# The Owner tag policies/plan/enforce-required-tags.rego requires. Set here rather than in the
# shopping list because these are platform-owned demo planes, not a product team's app.
variable "owner" {
  type        = string
  description = "Owning team for everything this env's app-factory vends; becomes the Owner tag."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9]|-[a-z0-9])*$", var.owner)) && length(var.owner) <= 40
    error_message = "owner must be lowercase alphanumeric/hyphen, <= 40 chars — it becomes an AWS tag value."
  }
}

# Posture-weakening, so it is a stack variable a team cannot reach. dev is ephemeral and autodeploys;
# stage/prod keep deletion protection and final snapshots.
variable "demo_teardown" {
  type        = bool
  description = "Let `terraform destroy` succeed in this env: force_destroy on buckets, no RDS deletion protection or final snapshot, 0-day secret recovery. Ephemeral envs only."
  default     = false
}
