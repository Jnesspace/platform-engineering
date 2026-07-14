# Minimal root for validate + registry: provider config here, required inputs only.
provider "aws" {}

module "object_storage" {
  source = "../.."

  name = "example-object-storage"
}
