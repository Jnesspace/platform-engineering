# PLAN (hardening-backlog #4): the nonadmin-launcher engine runs with Space-admin bound to its stack, so whoever can change patterns/nonadmin-launcher/engine/ can act as Space-admin. This is the server-side cap on what a run of that engine may produce, and it holds even when the engine's own Terraform is rewritten. Self-gating on the stack's labels, so it is safe to attach broadly.
package spacelift

import rego.v1

# Constants are prefixed because Spacelift evaluates each policy in isolation but `opa test`
# merges every file in policies/ into one package.
launcher_stack_labels := {"engine", "poc:nonadmin-launcher"}

# The engine vends app stacks, plus the terraform_data preconditions it gates itself with.
# terraform_data creates nothing and needs no credentials — it is the house plan-time gate idiom in
# all three engines (request_gate here, shopping_list_guard/cloud_guard/trust_guard in app-factory,
# catalog_gate/request_gate/permission_gate in iam-factory), so omitting it denied every run.
launcher_allowed_types := {"spacelift_stack", "terraform_data"}

# Never from an engine: a Space, a role grant, or a policy attachment would let it widen its
# own reach instead of just filling the Space it was pointed at.
launcher_forbidden_types := {
	"spacelift_space",
	"spacelift_role",
	"spacelift_role_attachment",
	"spacelift_policy",
	"spacelift_policy_attachment",
	"spacelift_user",
	"spacelift_api_key",
	"spacelift_worker_pool",
}

launcher_max_stacks := 10

launcher_name_pattern := `^[a-z0-9][a-z0-9-]{1,62}$`

# Provenance label the engine stamps on everything it vends.
launcher_required_label := "vended-by:onboarding-engine"

# Labels drive policy auto-attachment and the TRIGGER fan-out, so a vended stack labelling
# itself as an engine or as prod is a privilege claim, not cosmetics.
launcher_forbidden_labels := {
	"engine",
	"poc:nonadmin-launcher",
	"platform-factory",
	"elevated",
	"env:prod",
}

# project_root decides which Terraform a stack runs, so it is a privilege decision, not a setting.
# deny-privileged-iam.rego exempts stacks rooted here from its role-attachment deny; a vended stack
# pointed at the same path would inherit that exemption. Keep the two lists in step.
launcher_forbidden_project_roots := {"bootstrap/"}

# Optional pin. Empty leaves every structural check below in force; fill in the team Space ID
# and the engine can only ever build there.
launcher_allowed_space_ids := set()

engine_run if {
	some label in input.spacelift.stack.labels
	label in launcher_stack_labels
}

launcher_changed(r) if {
	some action in r.change.actions
	action in {"create", "update"}
}

vended_stacks := [r |
	some r in input.terraform.resource_changes
	r.type == "spacelift_stack"
	launcher_changed(r)
]

vended_target_spaces := {space |
	some r in vended_stacks
	space := r.change.after.space_id
	is_string(space)
}

deny contains msg if {
	engine_run
	some r in input.terraform.resource_changes
	launcher_changed(r)
	r.type in launcher_forbidden_types
	msg := sprintf("%s: an engine run must not manage %s — that would widen its own grant", [r.address, r.type])
}

deny contains msg if {
	engine_run
	some r in input.terraform.resource_changes
	launcher_changed(r)
	not r.type in launcher_allowed_types
	not r.type in launcher_forbidden_types
	msg := sprintf("%s: %s is not a resource type the onboarding engine produces", [r.address, r.type])
}

deny contains msg if {
	engine_run
	count(vended_stacks) > launcher_max_stacks
	msg := sprintf("engine run touches %d stacks; cap is %d", [count(vended_stacks), launcher_max_stacks])
}

# One run, one target Space. Anything else means the engine is no longer filling the Space it
# was pointed at.
deny contains msg if {
	engine_run
	count(vended_target_spaces) > 1
	msg := sprintf("engine run spans %d Spaces (%v); it may only build into one", [count(vended_target_spaces), sort(vended_target_spaces)])
}

deny contains msg if {
	engine_run
	some r in vended_stacks
	r.change.after.space_id == "root"
	msg := sprintf("%s targets the root Space; vended stacks belong in a team Space", [r.address])
}

deny contains msg if {
	engine_run
	count(launcher_allowed_space_ids) > 0
	some r in vended_stacks
	space := r.change.after.space_id
	is_string(space)
	not space in launcher_allowed_space_ids
	msg := sprintf("%s targets Space %q, which is not in the pinned set %v", [r.address, space, sort(launcher_allowed_space_ids)])
}

deny contains msg if {
	engine_run
	some r in vended_stacks
	name := r.change.after.name
	is_string(name)
	not regex.match(launcher_name_pattern, name)
	msg := sprintf("%s has name %q; vended stack names must match %s", [r.address, name, launcher_name_pattern])
}

deny contains msg if {
	engine_run
	some r in vended_stacks
	labels := r.change.after.labels
	is_array(labels)
	not launcher_required_label in labels
	msg := sprintf("%s is missing the %q provenance label", [r.address, launcher_required_label])
}

deny contains msg if {
	engine_run
	some r in vended_stacks
	some label in r.change.after.labels
	label in launcher_forbidden_labels
	msg := sprintf("%s claims the privileged label %q", [r.address, label])
}

# A vended stack rooted in bootstrap/ would run the root-admin bootstrap's Terraform, and
# deny-privileged-iam.rego exempts exactly that path — so this is the one way an engine could
# manufacture a stack that is allowed to mint role attachments. Closed here rather than there,
# because only this policy knows the run is an engine run.
deny contains msg if {
	engine_run
	some r in vended_stacks
	root := r.change.after.project_root
	is_string(root)
	some prefix in launcher_forbidden_project_roots
	startswith(root, prefix)
	msg := sprintf("%s points at project_root %q; an engine must not vend a stack into the %s bootstrap layer", [r.address, root, prefix])
}

# The engine must not hand out auto-apply: vended stacks pause at the confirm gate so the
# APPROVAL policy gets a say.
deny contains msg if {
	engine_run
	some r in vended_stacks
	r.change.after.autodeploy == true
	msg := sprintf("%s sets autodeploy; vended stacks must stop at the confirm gate", [r.address])
}

warn contains msg if {
	engine_run
	some r in vended_stacks
	"create" in r.change.actions

	# object.get rather than `not r.change.after.protect_from_deletion`: OPA hoists a nested
	# reference out of `not`, so an absent key would make the rule undefined, not true.
	object.get(r.change, ["after", "protect_from_deletion"], false) != true

	msg := sprintf("%s is created without protect_from_deletion", [r.address])
}

# Deleting a vended stack is legitimate offboarding, but it should never be a surprise.
warn contains msg if {
	engine_run
	some r in input.terraform.resource_changes
	r.type == "spacelift_stack"
	"delete" in r.change.actions
	msg := sprintf("%s will be deleted; confirm the team asked for this", [r.address])
}

sample := true
