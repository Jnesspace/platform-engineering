# Trivial placeholder workload for engine-vended stacks; the PoC proves creation, not the workload.
terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

resource "null_resource" "hello" {}

output "message" {
  value = "app-example placeholder vended by the onboarding engine"
}
