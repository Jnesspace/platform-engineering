# One-time ROOT-ADMIN bootstrap: for_each over var.environments stands up a per-env platform plane (dev/stage/prod git-promotion model).

# Auth via SPACELIFT_API_KEY_ENDPOINT / _ID / _SECRET (a root-admin key).
provider "spacelift" {}

module "env" {
  source   = "./env"
  for_each = var.environments

  environment        = each.key
  branch             = each.value.branch
  autodeploy         = each.value.autodeploy
  aws_integration_id = each.value.aws_integration_id
}
