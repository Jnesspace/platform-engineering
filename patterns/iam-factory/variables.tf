# No default: this is account-specific, and a stale subdomain silently pins every vended
# role's trust to the wrong OIDC issuer. bootstrap/iam-factory sets it via TF_VAR_.
variable "account_subdomain" {
  type        = string
  description = "Spacelift account subdomain, i.e. <this>.app.spacelift.io. Used as the OIDC issuer and audience."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,61}[a-z0-9]$", var.account_subdomain))
    error_message = "account_subdomain must be a DNS label — it is interpolated into the OIDC issuer URL and every trust-policy condition key."
  }
}

variable "create_oidc_provider" {
  type        = bool
  default     = true
  description = "Create the Spacelift OIDC provider in AWS. Set to false to reference an existing one instead."
}

# Must be the factory stack's own Space (or an ancestor in its admin subtree), or the run token can't manage the vended children.
variable "parent_space_id" {
  type        = string
  default     = "PLATFORM_ADMIN_SPACE_ID"
  description = "Space under which vended service Spaces are created (the factory's admin Space)."
}

# A service YAML may override parent_space, so the override has to be bounded: without this, a request could place a Space anywhere the factory token reaches.
variable "allowed_parent_space_ids" {
  type        = list(string)
  default     = []
  description = "Additional Space IDs a service YAML may name as `parent_space`. parent_space_id is always allowed; anything else fails the plan."
}

variable "default_permission_sets" {
  type        = list(string)
  default     = ["readonly"]
  description = "Permission sets granted when a service YAML omits `permissions:`. Must be names present in catalog.yaml."
}

variable "default_aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region exported into each vended Space's context (AWS_DEFAULT_REGION). IAM is global, but the AWS provider requires a region to initialize."
}

variable "max_vended_services" {
  type        = number
  default     = 25
  description = "Cap on services/*.yaml files processed in one run. Each mints a Space, an IAM role and a context, so an unbounded set is a blast-radius problem."

  validation {
    condition     = var.max_vended_services >= 1
    error_message = "max_vended_services must be at least 1."
  }
}

# --- The permissions boundary (runtime hard cap) ---

variable "boundary_mode" {
  type        = string
  default     = "catalog-services"
  description = "\"catalog-services\": the boundary allows only the AWS services catalog.yaml actually references (an allowlist that maintains itself from the catalog). \"allow-all\": Allow * with the deny list on top — the original denylist-only posture, for accounts where vended roles legitimately need services outside the catalog."

  validation {
    condition     = contains(["catalog-services", "allow-all"], var.boundary_mode)
    error_message = "boundary_mode must be \"catalog-services\" or \"allow-all\"."
  }
}

variable "boundary_extra_denied_actions" {
  type        = list(string)
  default     = []
  description = "Extra actions denied by the boundary, on top of the built-in escalation/control-plane list. Lets an operator tighten further without editing the pattern."
}

variable "allowed_regions" {
  type        = list(string)
  default     = []
  description = "When non-empty, every catalog grant is conditioned on aws:RequestedRegion — the most effective narrowing of a set that grants on Resource = \"*\". Left empty by default because global-endpoint services (S3 ListAllMyBuckets, STS, IAM) report us-east-1, so a careless lock breaks them silently."
}

variable "forbidden_catalog_action_prefixes" {
  type = list(string)
  default = [
    "*",
    "iam:",
    "organizations:",
    "account:",
    "sso:",
    "sso-directory:",
    "identitystore:",
    "sts:AssumeRole",
    "sts:GetFederationToken",
  ]
  description = "Action prefixes catalog.yaml may not grant. The boundary blocks these at runtime anyway; this makes them ungrantable in the first place, so the two layers can never drift into a false sense of scope."
}

# --- The OIDC trust (who can assume a vended role) ---

variable "trust_scopes" {
  type        = list(string)
  default     = ["write", "read"]
  description = "Spacelift OIDC `scope:` values the vended role trusts. Both by default so one ARN serves plans and applies; set to [\"read\"] to vend a plan-only twin, since proposed runs (PRs) otherwise receive write-capable credentials."

  validation {
    condition     = length(var.trust_scopes) > 0 && length(setsubtract(var.trust_scopes, ["read", "write"])) == 0
    error_message = "trust_scopes must be a non-empty subset of [\"read\", \"write\"]."
  }
}
