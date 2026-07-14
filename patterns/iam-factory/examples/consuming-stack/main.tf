##############################################################################
# Example: a developer's consuming stack in a vended Space.
#
# Reference only — the factory does NOT apply this. Copy it into a repo and
# point a Spacelift stack (living in a vended Space, e.g. `payments`) at it.
#
# IMPORTANT: this stack must be created with the Spacelift label `aws-oidc`
# so the factory's auto-attached context (labels = ["autoattach:aws-oidc"])
# injects TF_VAR_aws_role_arn. Without the label, the context does not attach
# and var.aws_role_arn is never set.
#
# What it proves: the run assumes the vended role via OIDC (no static keys),
# and sts:GetCallerIdentity shows the spacelift-<slug> role. Anything outside
# the service's catalog sets (or the boundary) is denied.
##############################################################################

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

# Proof of life: whoami under the vended role.
data "aws_caller_identity" "current" {}

output "assumed_identity" {
  value       = data.aws_caller_identity.current.arn
  description = "The identity this stack runs as — the vended spacelift-<slug> role."
}
