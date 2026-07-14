# Provider config lives in the root; Terraform eagerly configures every declared provider, so each cloud needs its own engine root.
provider "aws" {
  region = var.region
}
