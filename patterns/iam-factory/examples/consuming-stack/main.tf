# Reference-only consuming stack: it must carry the `aws-oidc` label or the factory's auto-attached context never injects TF_VAR_aws_role_arn.

variable "aws_role_arn" {
  type        = string
  description = "Injected by the factory's auto-attached context (requires the `aws-oidc` stack label)."
}

provider "aws" {
  assume_role_with_web_identity {
    role_arn = var.aws_role_arn
    # Spacelift writes the run's OIDC token here on every run.
    web_identity_token_file = "/mnt/workspace/spacelift.oidc"
  }
}

# Proof of life: whoami shows the vended spacelift-<slug> role.
data "aws_caller_identity" "current" {}

output "assumed_identity" {
  value       = data.aws_caller_identity.current.arn
  description = "The identity this stack runs as — the vended spacelift-<slug> role."
}
