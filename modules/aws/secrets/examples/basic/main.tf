# Minimal root for validate + registry: provider config here, required inputs only.
provider "aws" {}

module "secrets" {
  source = "../.."

  name = "example-secrets"
}
