# Coverage audit. Publishing a policy proves nothing; this proves the elevated stacks are actually
# reached by it, on a private worker pool, and undeletable — and fails the plan when one is not.

data "spacelift_spaces" "all" {}

data "spacelift_stacks" "all" {}

locals {
  spaces = { for s in data.spacelift_spaces.all.spaces : s.space_id => s }

  # Inheritance is the reachability rule: a stack can use a policy from its own Space, or from an
  # ancestor Space, as long as every Space on the path up inherits entities.
  parent_of = { for id, s in local.spaces : id => s.inherit_entities ? s.parent_space_id : null }

  # Six-level walk. Space trees are shallow; running out under-reports reachability, so a deeper
  # tree fails the audit loudly instead of passing it silently.
  anc1 = { for id, _ in local.spaces : id => local.parent_of[id] }
  anc2 = { for id, a in local.anc1 : id => a == null ? null : lookup(local.parent_of, a, null) }
  anc3 = { for id, a in local.anc2 : id => a == null ? null : lookup(local.parent_of, a, null) }
  anc4 = { for id, a in local.anc3 : id => a == null ? null : lookup(local.parent_of, a, null) }
  anc5 = { for id, a in local.anc4 : id => a == null ? null : lookup(local.parent_of, a, null) }
  anc6 = { for id, a in local.anc5 : id => a == null ? null : lookup(local.parent_of, a, null) }

  ancestry = {
    for id, _ in local.spaces : id => toset([
      for a in [id, local.anc1[id], local.anc2[id], local.anc3[id], local.anc4[id], local.anc5[id], local.anc6[id]] :
      a if a != null && a != ""
    ])
  }

  # Which published policies actually bind to each stack in the account.
  stack_coverage = {
    for s in data.spacelift_stacks.all.stacks : s.stack_id => sort(distinct([
      for k, p in local.publications : "${p.type} ${p.dir}/${p.slug}"
      if contains(lookup(local.ancestry, s.space_id, toset([s.space_id])), p.space)
      && (
        # LOGIN/NOTIFICATION are never attached; they apply by virtue of living in a reachable Space.
        contains(["LOGIN", "NOTIFICATION"], p.type)
        || contains(local.targets_by_policy[p.key], "*")
        || length(setintersection(local.targets_by_policy[p.key], s.labels)) > 0
      )
    ]))
  }

  elevated_stacks = [for s in data.spacelift_stacks.all.stacks : s if contains(s.labels, var.elevated_stack_label)]

  # An elevated run on a shared worker is docs/hardening-backlog.md item 5, unmitigated.
  elevated_on_shared_workers = [for s in local.elevated_stacks : s.stack_id if s.worker_pool_id == ""]

  # An elevated stack in a Space that cannot see the policy set is a guardrail that never fires.
  elevated_out_of_policy_reach = [
    for s in local.elevated_stacks : s.stack_id
    if length(setintersection(lookup(local.ancestry, s.space_id, toset([s.space_id])), var.policy_spaces)) == 0
  ]

  elevated_deletable = [for s in local.elevated_stacks : s.stack_id if !s.protect_from_deletion]

  elevated_audit = {
    for s in local.elevated_stacks : s.stack_id => {
      space                 = s.space_id
      worker_pool_id        = s.worker_pool_id
      protect_from_deletion = s.protect_from_deletion
      # Reported, not enforced: dev app-factory autodeploys by design (the promotion model).
      autodeploy = s.autodeploy
      policies   = local.stack_coverage[s.stack_id]
    }
  }
}

resource "terraform_data" "elevated_stack_audit" {
  count = var.enforce_elevated_stack_audit ? 1 : 0
  input = local.elevated_audit

  lifecycle {
    precondition {
      condition     = length(local.elevated_on_shared_workers) == 0
      error_message = "Elevated stacks on shared workers: ${join(", ", local.elevated_on_shared_workers)}. Set worker_pool_id on them (see worker-pools/) — an elevated token must not run next to co-tenant runs."
    }

    precondition {
      condition     = length(local.elevated_out_of_policy_reach) == 0
      error_message = "Elevated stacks no policy can reach: ${join(", ", local.elevated_out_of_policy_reach)}. Their Space neither is nor inherits from any of policy_spaces (${join(", ", var.policy_spaces)}). Add the Space to policy_spaces, or enable entity inheritance on it."
    }

    precondition {
      condition     = length(local.elevated_deletable) == 0
      error_message = "Elevated stacks without deletion protection: ${join(", ", local.elevated_deletable)}. Set protect_from_deletion = true."
    }
  }
}
