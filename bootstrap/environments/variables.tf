# No default: the integration ULIDs are account-specific, and a stale default pointing at someone
# else's AWS account is a real incident. The dev/stage/prod shape lives in terraform.tfvars.example.
# dev auto-deploys for fast iteration; stage/prod are gated (manual confirm) — the promotion gate.
variable "environments" {
  type = map(object({
    branch             = string
    autodeploy         = bool
    aws_integration_id = string
    # Opt-in per env, because it weakens posture: buckets get force_destroy and the database gives
    # up deletion protection and its final snapshot. Ephemeral lanes (dev) only.
    demo_teardown = optional(bool, false)
  }))
  description = "The environment list; adding an env here is the whole 'add an environment' procedure."

  validation {
    condition     = length(var.environments) > 0
    error_message = "environments must define at least one environment."
  }

  validation {
    condition     = alltrue([for e in keys(var.environments) : can(regex("^[a-z0-9][a-z0-9-]{0,30}$", e))])
    error_message = "Environment names must be lowercase alphanumeric/hyphen (they are baked into Space, stack and resource names)."
  }

  validation {
    condition     = alltrue([for e in var.environments : can(regex("^[0-9A-HJKMNP-TV-Z]{26}$", e.aws_integration_id))])
    error_message = "Each aws_integration_id must be a 26-character ULID. Use one integration per environment account."
  }

  validation {
    condition     = alltrue([for e in var.environments : can(regex("^[A-Za-z0-9._/-]+$", e.branch))])
    error_message = "Each branch must be a valid git ref name fragment."
  }
}

variable "repository" {
  type        = string
  description = "Repository backing every env's stacks (name only, via the default VCS integration)."

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+$", var.repository))
    error_message = "repository is a bare repository name (no owner/ prefix, no slashes)."
  }
}

variable "region" {
  type        = string
  description = "AWS region for the envs' vended resources."

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must look like us-east-1 / eu-central-1 / ap-southeast-2."
  }
}

variable "parent_space" {
  type        = string
  default     = "root"
  description = "Parent Space for the env Spaces."

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$", var.parent_space))
    error_message = "parent_space must be a Space ID (slug), e.g. \"root\"."
  }
}

# Resolved by name via data.spacelift_worker_pools — see worker-pools/README.md for why not a ULID.
variable "elevated_worker_pool_name" {
  type        = string
  default     = "elevated-engines"
  description = "Name of the private worker pool the app-factory stacks must run on (from worker-pools/)."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,62}$", var.elevated_worker_pool_name))
    error_message = "elevated_worker_pool_name must be lowercase alphanumeric/hyphen, 2-63 chars."
  }
}

# Becomes the Owner tag on everything each env's app-factory vends. These planes are platform-owned
# demo environments, not a product team's app, so it is set here rather than in a shopping list.
variable "owner" {
  type        = string
  default     = "platform"
  description = "Owning team recorded on every vended resource (policies/plan/enforce-required-tags.rego requires it)."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9]|-[a-z0-9])*$", var.owner)) && length(var.owner) <= 40
    error_message = "owner must be lowercase alphanumeric/hyphen, <= 40 chars — it becomes an AWS tag value."
  }
}
