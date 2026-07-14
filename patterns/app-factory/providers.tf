# Provider CONFIG lives in the root, never in the modules. This engine is the
# AWS path (the cloud wired live). Terraform eagerly configures every declared
# provider — so one root can't span clouds without every cloud's credentials.
# The azure/gcp modules use the identical interface, so an azure/gcp engine is
# this same file with its provider + the modules/<cloud>/* blocks swapped in.
provider "aws" {
  region = var.region
}
