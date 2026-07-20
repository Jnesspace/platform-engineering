# app-factory (AWS path): composes modules/aws/* from platform.yaml and aggregates their IAM into one app role (iam.tf); each cloud gets its own root because Terraform eagerly configures every declared provider.

locals {
  shopping_list_path = startswith(var.shopping_list_file, "/") ? var.shopping_list_file : "${path.root}/${var.shopping_list_file}"
  # Inline YAML (Blueprint/form path) wins over the file (git path).
  spec = yamldecode(var.shopping_list_yaml != "" ? var.shopping_list_yaml : file(local.shopping_list_path))

  cloud    = try(local.spec.cloud, "aws")
  app_name = var.app_name != "" ? var.app_name : try(local.spec.name, "app")

  tags = {
    app        = local.app_name
    managed_by = "app-factory"
  }

  resources      = try(local.spec.resources, {})
  object_storage = { for r in try(local.resources.object_storage, []) : r.name => r }
  secrets        = { for r in try(local.resources.secrets, []) : r.name => r }
  databases      = { for r in try(local.resources.database, []) : r.name => r }
  compute        = { for r in try(local.resources.compute, []) : r.name => r }
}

# Fail fast if the shopping list asks for a cloud this engine doesn't serve.
resource "terraform_data" "cloud_guard" {
  lifecycle {
    precondition {
      condition     = local.cloud == "aws"
      error_message = "This engine is the AWS path; the shopping list requests cloud '${local.cloud}'. Azure/GCP use the same modules with their own provider — see modules/${local.cloud}/ and the README."
    }
  }
}

module "object_storage" {
  source   = "../../modules/aws/object-storage"
  for_each = local.object_storage

  name = "${local.app_name}-${each.key}"
  tags = local.tags
}

module "secrets" {
  source   = "../../modules/aws/secrets"
  for_each = local.secrets

  name = "${local.app_name}-${each.key}"
  tags = local.tags
}

module "database" {
  source   = "../../modules/aws/database"
  for_each = local.databases

  name = "${local.app_name}-${each.key}"
  tags = local.tags
}

module "compute" {
  source   = "../../modules/aws/compute"
  for_each = local.compute

  name = "${local.app_name}-${each.key}"
  tags = local.tags
}
