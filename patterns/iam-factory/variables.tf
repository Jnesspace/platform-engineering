variable "account_subdomain" {
  type        = string
  default     = "jnesspace"
  description = "Spacelift account subdomain, i.e. <this>.app.spacelift.io. Used as the OIDC issuer and audience."
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
