# The built-in "Space admin" system role. The role binding hands THIS to the
# engine stack (scoped to the team Space) — never to a product-team user.
# By default it is resolved at plan time from the system role's slug, so no
# account-specific ULID needs to be hardcoded.
variable "space_admin_role_id" {
  type        = string
  default     = null
  description = "Optional override; if null, resolved from the system 'space-admin' role."
}

variable "repository" {
  type        = string
  default     = "platform-engineering"
  description = "Repository backing the engine stack (default GitHub App integration)."
}

variable "branch" {
  type        = string
  default     = "main"
  description = "Tracked branch for the engine stack."
}

variable "engine_project_root" {
  type        = string
  default     = "patterns/nonadmin-launcher/engine"
  description = "Directory in the repo holding the admin-owned engine code."
}

variable "team_name" {
  type        = string
  default     = "cpe-team1"
  description = "Product team Space name (and slug basis for its resources)."
}

variable "platform_space_name" {
  type        = string
  default     = "platform"
  description = "Governance-plane Space name. Override for isolated test instances."
}

variable "engine_stack_name" {
  type        = string
  default     = "onboarding-engine"
  description = "Engine stack name. Override for isolated test instances."
}
