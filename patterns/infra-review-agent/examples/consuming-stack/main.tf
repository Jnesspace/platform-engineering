# Reference-only consuming stack: give its spacelift_stack the `infra-review`
# label and the auto-attached context reviews every proposed run's plan. The
# stack's own code needs nothing — the context delivers script, config, hooks.

resource "terraform_data" "proof" {
  input = {
    service     = "demo"
    environment = "dev"
  }
}

output "proof" {
  value       = terraform_data.proof.output
  description = "Something for the plan to contain so the review agent has a change to look at."
}
