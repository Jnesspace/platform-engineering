# PLAN: deny plans that create more than max_new_resources resources at once.
package spacelift

import rego.v1

max_new_resources := 25

created := [r | some r in input.terraform.resource_changes; "create" in r.change.actions]

deny contains msg if {
	count(created) > max_new_resources
	msg := sprintf("plan creates %d resources; cap is %d", [count(created), max_new_resources])
}

sample := true
