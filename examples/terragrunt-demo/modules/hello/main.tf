# Stand-in for a registry module, kept credential-free on purpose so the stack
# proves the Terragrunt + OpenTofu runner works without depending on a cloud
# integration. Swap `source` in the unit for a Spacelift registry reference
# once the AWS modules are published.

terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

variable "name" {
  type        = string
  description = "Logical name of the thing this unit manages."
}

variable "environment" {
  type        = string
  description = "Environment lane the unit belongs to."
}

variable "owner" {
  type        = string
  description = "Owning team, recorded for the audit trail."
}

resource "null_resource" "unit" {
  triggers = {
    name        = var.name
    environment = var.environment
    owner       = var.owner
  }
}

output "unit_id" {
  value       = "${var.name}-${var.environment}"
  description = "Proves the unit's inputs reached OpenTofu through Terragrunt."
}

output "managed_by" {
  value       = "Terragrunt unit -> OpenTofu, owned by ${var.owner}"
  description = "Printed in the run log as the demo's money line."
}
