# PLAN (hardening-backlog #6): the iam-factory holds platform-admin over Space and IAM vending — the biggest blast radius in the repo. patterns/iam-factory/main.tf already gates itself twice (a terraform_data catalog precondition and an AWS permissions boundary), but both live in the engine's own code and vanish the moment that code is edited. This is the third layer, server-side: it constrains the SHAPE of a factory run. The IAM documents themselves are checked in iam-factory-trust-boundary.rego.
package spacelift

import rego.v1

# Constants are prefixed because Spacelift evaluates each policy in isolation but `opa test`
# merges every file in policies/ into one package.
factory_stack_labels := {"platform-factory"}

# Everything patterns/iam-factory/main.tf legitimately manages. Anything else in the plan
# means the engine is no longer the engine.
factory_allowed_types := {
	"spacelift_space",
	"spacelift_context",
	"spacelift_environment_variable",
	"terraform_data",
	"aws_iam_role",
	"aws_iam_role_policy",
	"aws_iam_policy",
	"aws_iam_openid_connect_provider",
	"tls_certificate",
}

# Called out separately from the allowlist so the message says *why*, not just "unexpected".
factory_escalation_types := {
	"spacelift_role",
	"spacelift_role_attachment",
	"spacelift_policy",
	"spacelift_policy_attachment",
	"spacelift_stack",
	"spacelift_user",
	"spacelift_api_key",
	"spacelift_idp_group_mapping",
}

factory_max_spaces := 10

# The name shape the terraform_data precondition enforces; re-checked here because a tampered
# engine simply deletes the precondition.
factory_role_name_pattern := `^spacelift-[a-z0-9-]{1,54}$`

# A context labelled autoattach:<label> injects its environment into every stack carrying that
# label, so the label is a distribution list. Keep it to the one the factory needs.
factory_allowed_autoattach := {"autoattach:aws-oidc"}

# Optional pin: the platform-admin Space ID. Empty leaves the structural checks in force; set
# it and vended Spaces can only ever hang off that parent.
factory_allowed_parents := set()

factory_run if {
	some label in input.spacelift.stack.labels
	label in factory_stack_labels
}

factory_changed(r) if {
	some action in r.change.actions
	action in {"create", "update"}
}

vended_spaces := [r |
	some r in input.terraform.resource_changes
	r.type == "spacelift_space"
	factory_changed(r)
]

deny contains msg if {
	factory_run
	some r in input.terraform.resource_changes
	factory_changed(r)
	r.type in factory_escalation_types
	msg := sprintf("%s: the factory must not manage %s — elevation is created by the root-admin bootstrap", [r.address, r.type])
}

deny contains msg if {
	factory_run
	some r in input.terraform.resource_changes
	factory_changed(r)
	not r.type in factory_allowed_types
	not r.type in factory_escalation_types
	msg := sprintf("%s: %s is not a resource type the iam-factory produces", [r.address, r.type])
}

deny contains msg if {
	factory_run
	count(vended_spaces) > factory_max_spaces
	msg := sprintf("factory run touches %d Spaces; cap is %d", [count(vended_spaces), factory_max_spaces])
}

# Vended Spaces are children of platform-admin. A Space parented at root is a sibling of the
# admin plane rather than something inside it.
deny contains msg if {
	factory_run
	some r in vended_spaces
	r.change.after.parent_space_id == "root"
	msg := sprintf("%s is parented at root; vended Spaces must hang off the platform-admin Space", [r.address])
}

deny contains msg if {
	factory_run
	count(factory_allowed_parents) > 0
	some r in vended_spaces
	parent := r.change.after.parent_space_id
	is_string(parent)
	not parent in factory_allowed_parents
	msg := sprintf("%s is parented at %q, which is not in the pinned set %v", [r.address, parent, sort(factory_allowed_parents)])
}

# Toggling inheritance is root-admin-only (hardening-backlog #7) and the factory runs with
# Space-admin. Denying it here turns a confusing API error into a clear one.
deny contains msg if {
	factory_run
	some r in vended_spaces
	r.change.after.inherit_entities == false
	msg := sprintf("%s sets inherit_entities = false; only the root-admin bootstrap may change inheritance", [r.address])
}

deny contains msg if {
	factory_run
	some r in input.terraform.resource_changes
	r.type == "aws_iam_role"
	factory_changed(r)
	name := r.change.after.name
	is_string(name)
	not regex.match(factory_role_name_pattern, name)
	msg := sprintf("%s mints role %q; vended role names must match %s", [r.address, name, factory_role_name_pattern])
}

deny contains msg if {
	factory_run
	some r in input.terraform.resource_changes
	r.type == "spacelift_context"
	factory_changed(r)
	some label in r.change.after.labels
	startswith(label, "autoattach:")
	not label in factory_allowed_autoattach
	msg := sprintf("%s auto-attaches on %q; the factory may only use %v", [r.address, label, sort(factory_allowed_autoattach)])
}

# The OIDC audience is what AWS checks the token against. Anything but a Spacelift issuer
# means the provider would trust a foreign IdP.
deny contains msg if {
	factory_run
	some r in input.terraform.resource_changes
	r.type == "aws_iam_openid_connect_provider"
	factory_changed(r)
	some client_id in r.change.after.client_id_list
	not endswith(client_id, ".app.spacelift.io")
	msg := sprintf("%s trusts audience %q, which is not a Spacelift issuer", [r.address, client_id])
}

sample := true
