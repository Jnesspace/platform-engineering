# The audit surface: one place that answers "which policy binds to which stack, and how".

output "published_policies" {
  description = "Every .rego published: its Spacelift type, Space, Rego engine and autoattach targets."
  value = {
    for k, p in local.publications : k => {
      type       = p.type
      space      = p.space
      engine     = strcontains(p.body, "import rego.v1") ? "REGO_V1" : "REGO_V0"
      autoattach = sort(tolist(local.targets_by_policy[p.key]))
      policy_id  = spacelift_policy.governed[k].id
    }
  }
}

# A policy that is discovered but not published must say so here, or the only signal is its absence
# from published_policies — which reads identically to "someone deleted the file".
output "skipped_policies" {
  description = "Discovered .rego files deliberately not published, and why."
  value       = local.skipped
}

output "stack_coverage" {
  description = "Per stack in the account, the published policies that actually bind to it. Empty means ungoverned."
  value       = local.stack_coverage
}

output "elevated_stack_audit" {
  description = "Per elevated stack: worker pool, deletion protection, autodeploy and effective policy coverage."
  value       = local.elevated_audit
}

output "ungoverned_stacks" {
  description = "Stacks no published policy reaches — the list that should stay empty."
  value       = sort([for id, policies in local.stack_coverage : id if length(policies) == 0])
}
