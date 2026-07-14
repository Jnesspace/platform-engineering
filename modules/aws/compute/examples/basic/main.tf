# Minimal root for validate + registry: provider config here, required inputs only.
provider "aws" {}

module "compute" {
  source = "../.."

  name = "example-compute"
}
