# PLAN: deny changes that add or remove env:* labels on spacelift_stack resources.
package spacelift

import rego.v1

env_labels(obj) := {l | some l in obj.labels; startswith(l, "env:")}

deny contains msg if {
	some r in input.terraform.resource_changes
	r.type == "spacelift_stack"
	"update" in r.change.actions
	before := env_labels(r.change.before)
	after := env_labels(r.change.after)
	before != after
	msg := sprintf("%s changes protected env:* labels: %v -> %v", [r.address, sort(before), sort(after)])
}

sample := true
