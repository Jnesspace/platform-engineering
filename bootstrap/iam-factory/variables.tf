# Nothing account-specific has a default: this root is applied against whatever account holds the
# root-admin key, and a stale default silently pointing at someone else's account is a real incident.

variable "account_subdomain" {
  type        = string
  description = "Spacelift account subdomain (the <x> in <x>.app.spacelift.io); becomes the factory's OIDC issuer and audience."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.account_subdomain))
    error_message = "account_subdomain must be a DNS label: lowercase alphanumerics and hyphens, not starting or ending with a hyphen."
  }
}

variable "aws_integration_id" {
  type        = string
  description = "AWS integration (ULID) the factory runs on. Its role trust must already accept this Spacelift account."

  validation {
    condition     = can(regex("^[0-9A-HJKMNP-TV-Z]{26}$", var.aws_integration_id))
    error_message = "aws_integration_id must be a 26-character ULID (Crockford base32, uppercase)."
  }
}

variable "aws_region" {
  type        = string
  description = "Region for the factory's AWS provider (IAM is global; the provider still needs one)."

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.aws_region))
    error_message = "aws_region must look like us-east-1 / eu-central-1 / ap-southeast-2."
  }
}

variable "repository" {
  type        = string
  description = "Repository backing the factory stack (name only, via the default VCS integration)."

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+$", var.repository))
    error_message = "repository is a bare repository name (no owner/ prefix, no slashes)."
  }
}

# The stack executes whatever is on this branch WITH Space-admin, so it must be a protected branch.
variable "branch" {
  type        = string
  default     = "main"
  description = "Tracked branch for the factory stack. Must be branch-protected (hardening item 1)."

  validation {
    condition     = can(regex("^[A-Za-z0-9._/-]+$", var.branch))
    error_message = "branch must be a valid git ref name fragment."
  }
}

variable "project_root" {
  type        = string
  default     = "patterns/iam-factory"
  description = "Directory in the repo holding the factory code."

  validation {
    condition     = can(regex("^[A-Za-z0-9._/-]+$", var.project_root)) && !startswith(var.project_root, "/")
    error_message = "project_root must be a repo-relative path with no leading slash."
  }
}

variable "space_name" {
  type        = string
  default     = "platform-admin"
  description = "Name of the admin-plane Space the factory lives in."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,62}$", var.space_name))
    error_message = "space_name must be lowercase alphanumeric/hyphen, 2-63 chars."
  }
}

variable "space_admin_role_id" {
  type        = string
  default     = null
  description = "Optional override; if null, resolved from the system 'space-admin' role."

  validation {
    condition     = var.space_admin_role_id == null || can(regex("^[0-9A-HJKMNP-TV-Z]{26}$", var.space_admin_role_id))
    error_message = "space_admin_role_id must be a 26-character ULID, or null to resolve by slug."
  }
}

variable "create_oidc_provider" {
  type        = bool
  default     = true
  description = "Whether factory runs create the AWS OIDC provider. Set false if it already exists in the account."
}

# Resolved by name via data.spacelift_worker_pools — see worker-pools/README.md for why not a ULID.
variable "elevated_worker_pool_name" {
  type        = string
  default     = "elevated-engines"
  description = "Name of the private worker pool the factory stack must run on (from worker-pools/)."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,62}$", var.elevated_worker_pool_name))
    error_message = "elevated_worker_pool_name must be lowercase alphanumeric/hyphen, 2-63 chars."
  }
}

# Root-admin-only lever, deliberately exposed here and nowhere else. TRUE is required as long as the
# AWS integration lives in `root`: the factory stack, the private worker pool and the governance
# policy set are all root-level entities, and inheritance is how this Space reaches them.
# See README "Inheritance and hardening item 7" before touching it.
variable "inherit_entities" {
  type        = bool
  default     = true
  description = "Whether the admin-plane Space inherits root entities. false requires the AWS integration, worker pool and policy set to live in this Space."
}
