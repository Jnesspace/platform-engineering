# Minimal root for validate + registry: provider config here, required inputs only.
provider "aws" {}

module "database" {
  source = "../.."

  name = "example-database"
}
