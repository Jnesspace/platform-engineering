# Publishes the blueprints/ catalog as live, deployable Spacelift Blueprints.
# Applied with a root-admin key. Each blueprint deploys via patterns/app-factory
# (same modules as the GitOps path) with the AWS integration attached.
provider "spacelift" {}

variable "space" {
  type        = string
  default     = "root"
  description = "Space the blueprint catalog is published in (controls who sees it)."

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$", var.space))
    error_message = "space must be a Space ID (slug), e.g. \"root\"."
  }
}

locals {
  catalog = {
    object-storage = { name = "Object storage (S3 bucket)", description = "Vend an S3 bucket for an app." }
    database       = { name = "Database (PostgreSQL)", description = "Vend a Postgres database for an app." }
    secrets        = { name = "Secret (Secrets Manager)", description = "Vend a Secrets Manager secret for an app." }
    compute        = { name = "Compute (EC2 instance)", description = "Vend an EC2 instance for an app." }
    app            = { name = "App bundle (storage + secret + role)", description = "Vend a standard app: bucket + secret + one scoped IAM role." }
  }
}

resource "spacelift_blueprint" "catalog" {
  for_each = local.catalog

  name        = each.value.name
  space       = var.space
  state       = "PUBLISHED"
  description = each.value.description
  template    = file("${path.module}/../../blueprints/${each.key}.yaml")
  labels      = ["catalog", "platform-engineering"]
}

output "published" {
  value       = { for k, b in spacelift_blueprint.catalog : k => b.id }
  description = "Catalog key => blueprint ID."
}
