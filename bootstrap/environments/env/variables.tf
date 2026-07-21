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
  description = "AWS integration for this env — ideally one per env account; shared only on the demo account."
}

variable "region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region for the env's vended resources."
}

variable "parent_space" {
  type        = string
  default     = "root"
  description = "Parent Space for the env Space."
}

variable "repository" {
  type        = string
  default     = "platform-engineering"
  description = "Repository backing the env's stacks (default GitHub App integration)."
}

variable "autodeploy" {
  type        = bool
  description = "true = merges apply unattended (dev); false = runs pause at the confirm gate (stage/prod)."
}
