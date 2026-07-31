# Resolved from the system role slug by default; the binding hands this to the ENGINE STACK, never a user.
variable "space_admin_role_id" {
  type        = string
  default     = null
  description = "Optional override; if null, resolved from the system 'space-admin' role."

  validation {
    condition     = var.space_admin_role_id == null || can(regex("^[0-9A-HJKMNP-TV-Z]{26}$", var.space_admin_role_id))
    error_message = "space_admin_role_id must be a 26-character ULID, or null to resolve by slug."
  }
}

variable "repository" {
  type        = string
  description = "Repository backing the engine stack (name only, via the default VCS integration)."

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+$", var.repository))
    error_message = "repository is a bare repository name (no owner/ prefix, no slashes)."
  }
}

# The engine executes whatever is on this branch WITH Space-admin, so it must be a protected branch.
variable "branch" {
  type        = string
  default     = "main"
  description = "Tracked branch for the engine stack. Must be branch-protected (hardening item 1)."

  validation {
    condition     = can(regex("^[A-Za-z0-9._/-]+$", var.branch))
    error_message = "branch must be a valid git ref name fragment."
  }
}

variable "engine_project_root" {
  type        = string
  default     = "patterns/nonadmin-launcher/engine"
  description = "Directory in the repo holding the admin-owned engine code."

  validation {
    condition     = can(regex("^[A-Za-z0-9._/-]+$", var.engine_project_root)) && !startswith(var.engine_project_root, "/")
    error_message = "engine_project_root must be a repo-relative path with no leading slash."
  }
}

# Required: which team is being onboarded is a per-deployment fact, not a default.
variable "team_name" {
  type        = string
  description = "Product team Space name (and slug basis for its resources)."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,62}$", var.team_name))
    error_message = "team_name must be lowercase alphanumeric/hyphen, 2-63 chars."
  }
}

variable "platform_space_name" {
  type        = string
  default     = "platform"
  description = "Governance-plane Space name. Override for isolated test instances."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,62}$", var.platform_space_name))
    error_message = "platform_space_name must be lowercase alphanumeric/hyphen, 2-63 chars."
  }
}

variable "engine_stack_name" {
  type        = string
  default     = "onboarding-engine"
  description = "Engine stack name. Override for isolated test instances."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,62}$", var.engine_stack_name))
    error_message = "engine_stack_name must be lowercase alphanumeric/hyphen, 2-63 chars."
  }
}

# Resolved by name via data.spacelift_worker_pools — see worker-pools/README.md for why not a ULID.
variable "elevated_worker_pool_name" {
  type        = string
  default     = "elevated-engines"
  description = "Name of the private worker pool the engine stack must run on (from worker-pools/)."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,62}$", var.elevated_worker_pool_name))
    error_message = "elevated_worker_pool_name must be lowercase alphanumeric/hyphen, 2-63 chars."
  }
}

# TRUE by default, and that is a change of posture — see README "Why the governance plane inherits".
# Entity inheritance is the transport for governance as well as for credentials: with it off, neither
# the root worker pool nor the root policy set can reach the engine stack, which is the single most
# privileged object in the account. The TEAM Space, where team-authored code runs, stays off.
variable "platform_space_inherit_entities" {
  type        = bool
  default     = true
  description = "Whether the governance-plane Space inherits root entities (needed for the root worker pool and policy set)."
}

variable "team_space_inherit_entities" {
  type        = bool
  default     = false
  description = "Whether the team Space inherits root entities. Keep false; reach it by adding it to bootstrap/governance policy_spaces."
}
