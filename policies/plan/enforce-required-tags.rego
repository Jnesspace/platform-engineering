# PLAN: deny resources created or updated without the required tags.
package spacelift

import rego.v1

required_tags := {"Environment", "Project", "Owner"}

deny contains msg if {
	some r in input.terraform.resource_changes
	some action in r.change.actions
	action in {"create", "update"}
	tags := r.change.after.tags_all
	missing := {t | some t in required_tags; not tags[t]}
	count(missing) > 0
	msg := sprintf("%s is missing required tags: %s", [r.address, concat(", ", sort(missing))])
}

sample := true
