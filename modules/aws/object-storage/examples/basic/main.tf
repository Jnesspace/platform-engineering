# Minimal root: provider config lives here (never in the module), and the
# module is called with only its required inputs. Used for validate + registry.
provider "aws" {}

module "object_storage" {
  source = "../.."

  name = "example-object-storage"
}
