# PLAN: env:* labels are the promotion lanes (bootstrap/environments) and drive policy auto-attachment, so relabelling a stack is a privilege change. Deny it when the plan shows it; warn when the plan cannot show it.
package spacelift

import rego.v1

# The guardrail-gating labels are privilege claims for exactly the same reason env:* is: they
# decide which PLAN policies evaluate a stack (launcher-engine-guardrail, iam-factory-guardrail,
# trust-boundary) and which stacks get proposed-run withholding (proposed-run-safety). Kept in
# agreement with those files by the consistency test in policies/plan/tests/.
guardrail_labels := {"engine", "poc:nonadmin-launcher", "platform-factory", "app-factory", "elevated"}

env_labels(labels) := {l |
	some l in labels
	startswith(l, "env:")
} | {l |
	some l in labels
	l in guardrail_labels
}

deny contains msg if {
	some r in input.terraform.resource_changes
	r.type == "spacelift_stack"
	"update" in r.change.actions

	# Only compare when both sides are actually present. Terraform omits unknown values
	# from `after` entirely, so a missing key would otherwise read as "all labels removed".
	is_array(r.change.before.labels)
	is_array(r.change.after.labels)

	before := env_labels(r.change.before.labels)
	after := env_labels(r.change.after.labels)
	before != after

	msg := sprintf("%s changes protected labels (env:* lanes or guardrail-gating labels): %v -> %v", [r.address, sort(before), sort(after)])
}

# Labels unknown at plan time: cannot prove the lane is unchanged, so force a human look
# rather than fail a legitimate run or wave through a relabelling.
warn contains msg if {
	some r in input.terraform.resource_changes
	r.type == "spacelift_stack"
	"update" in r.change.actions
	is_array(r.change.before.labels)
	count(env_labels(r.change.before.labels)) > 0

	# object.get, not `not is_array(r.change.after.labels)`: OPA hoists a nested reference out
	# of `not`, so the negation of an absent key is undefined rather than true — the rule would
	# never fire in exactly the case it exists for.
	not is_array(object.get(r.change, ["after", "labels"], null))

	msg := sprintf("%s has env:* labels but its new labels are unknown at plan time; confirm the lane is unchanged", [r.address])
}

sample := true
