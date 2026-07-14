# Placeholder workload for the stacks the onboarding engine vends into the team
# Space. Kept trivial — the PoC proves the engine can CREATE these stacks with
# elevated permissions, not that the workload does anything.
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
