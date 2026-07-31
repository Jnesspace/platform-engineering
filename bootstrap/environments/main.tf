# One-time ROOT-ADMIN bootstrap: for_each over var.environments stands up a per-env platform plane (dev/stage/prod git-promotion model).

# Auth via SPACELIFT_API_KEY_ENDPOINT / _ID / _SECRET (a root-admin key).
provider "spacelift" {}

# The pool is created by worker-pools/ and found by NAME, so no ULID crosses the root boundary.
data "spacelift_worker_pools" "all" {}

locals {
  elevated_pools          = [for p in data.spacelift_worker_pools.all.worker_pools : p if p.name == var.elevated_worker_pool_name]
  elevated_worker_pool_id = length(local.elevated_pools) == 1 ? local.elevated_pools[0].worker_pool_id : null
}

# Resolved once here rather than per env; gated so a missing pool fails the plan instead of quietly
# putting a write-enabled AWS integration on shared workers.
resource "terraform_data" "worker_pool_gate" {
  input = var.elevated_worker_pool_name

  lifecycle {
    precondition {
      condition     = local.elevated_worker_pool_id != null
      error_message = "Expected exactly one worker pool named '${var.elevated_worker_pool_name}', found ${length(local.elevated_pools)}. Apply worker-pools/ first — an elevated token must not fall back to shared workers."
    }
  }
}

module "env" {
  source   = "./env"
  for_each = var.environments

  environment        = each.key
  branch             = each.value.branch
  autodeploy         = each.value.autodeploy
  aws_integration_id = each.value.aws_integration_id
  demo_teardown      = each.value.demo_teardown

  repository     = var.repository
  region         = var.region
  parent_space   = var.parent_space
  owner          = var.owner
  worker_pool_id = local.elevated_worker_pool_id
}
