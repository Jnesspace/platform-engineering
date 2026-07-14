# app-factory: turns a developer's shopping list (platform.yaml) into cloud
# resources by composing the dual-purpose modules under modules/<cloud>/.
# Module sources are static in Terraform, so cloud selection is done by gating
# each cloud's module blocks with a conditional for_each: the selected cloud
# gets a map of requested resources, the other two get {}.

locals {
  shopping_list_path = startswith(var.shopping_list_file, "/") ? var.shopping_list_file : "${path.root}/${var.shopping_list_file}"
  spec               = yamldecode(file(local.shopping_list_path))

  cloud    = try(local.spec.cloud, var.cloud)
  app_name = var.app_name != "" ? var.app_name : try(local.spec.name, "app")

  tags = {
    app        = local.app_name
    managed_by = "app-factory"
  }

  # Shopping-list entries keyed by logical name; each primitive key is optional.
  resources      = try(local.spec.resources, {})
  object_storage = { for r in try(local.resources.object_storage, []) : r.name => r }
  secrets        = { for r in try(local.resources.secrets, []) : r.name => r }
  databases      = { for r in try(local.resources.database, []) : r.name => r }
  compute        = { for r in try(local.resources.compute, []) : r.name => r }

  is_aws   = local.cloud == "aws"
  is_azure = local.cloud == "azure"
  is_gcp   = local.cloud == "gcp"
}

# ------------------------------- AWS ---------------------------------------

module "aws_object_storage" {
  source   = "../../modules/aws/object-storage"
  for_each = local.is_aws ? local.object_storage : {}

  name = "${local.app_name}-${each.key}"
  tags = local.tags
}

module "aws_secrets" {
  source   = "../../modules/aws/secrets"
  for_each = local.is_aws ? local.secrets : {}

  name = "${local.app_name}-${each.key}"
  tags = local.tags
}

module "aws_database" {
  source   = "../../modules/aws/database"
  for_each = local.is_aws ? local.databases : {}

  name = "${local.app_name}-${each.key}"
  tags = local.tags
}

module "aws_compute" {
  source   = "../../modules/aws/compute"
  for_each = local.is_aws ? local.compute : {}

  name = "${local.app_name}-${each.key}"
  tags = local.tags
}

# ------------------------------- Azure -------------------------------------

module "azure_object_storage" {
  source   = "../../modules/azure/object-storage"
  for_each = local.is_azure ? local.object_storage : {}

  name                = "${local.app_name}-${each.key}"
  resource_group_name = var.resource_group_name
  tags                = local.tags
}

module "azure_secrets" {
  source   = "../../modules/azure/secrets"
  for_each = local.is_azure ? local.secrets : {}

  name                = "${local.app_name}-${each.key}"
  resource_group_name = var.resource_group_name
  tags                = local.tags
}

module "azure_database" {
  source   = "../../modules/azure/database"
  for_each = local.is_azure ? local.databases : {}

  name                = "${local.app_name}-${each.key}"
  resource_group_name = var.resource_group_name
  tags                = local.tags
}

module "azure_compute" {
  source   = "../../modules/azure/compute"
  for_each = local.is_azure ? local.compute : {}

  name                = "${local.app_name}-${each.key}"
  resource_group_name = var.resource_group_name
  tags                = local.tags
}

# ------------------------------- GCP ---------------------------------------

module "gcp_object_storage" {
  source   = "../../modules/gcp/object-storage"
  for_each = local.is_gcp ? local.object_storage : {}

  name    = "${local.app_name}-${each.key}"
  project = var.project
  labels  = local.tags
}

module "gcp_secrets" {
  source   = "../../modules/gcp/secrets"
  for_each = local.is_gcp ? local.secrets : {}

  name    = "${local.app_name}-${each.key}"
  project = var.project
  labels  = local.tags
}

module "gcp_database" {
  source   = "../../modules/gcp/database"
  for_each = local.is_gcp ? local.databases : {}

  name    = "${local.app_name}-${each.key}"
  project = var.project
  labels  = local.tags
}

module "gcp_compute" {
  source   = "../../modules/gcp/compute"
  for_each = local.is_gcp ? local.compute : {}

  name    = "${local.app_name}-${each.key}"
  project = var.project
  zone    = var.zone
  labels  = local.tags
}
