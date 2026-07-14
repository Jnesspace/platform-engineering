# Minimal root: provider config lives here (never in the module), and the
# module is called with only its required inputs. Used for validate + registry.
provider "aws" {}

module "secrets" {
  source = "../.."

  name = "example-secrets"
}
