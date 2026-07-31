# PLAN: a blast-radius fuse. A runaway for_each over a bad YAML file is the likeliest way this repo's engines do damage, and it always shows up as a huge create count. Two caps, because one number cannot serve both halves: cloud resources cost money and hold data, Spacelift control-plane objects do neither and their legitimate fan-out is an order of magnitude larger.
package spacelift

import rego.v1

# Cloud infrastructure: buckets, databases, IAM roles. app-factory's shopping_list_guard caps a
# request at 25 entries (var.max_resources, itself capped at 25), so this is that number's
# server-side twin — the one an edited engine cannot delete.
max_new_resources := 25

# Spacelift control-plane objects. Legitimate fan-out here is multiplicative and repo-determined:
# bootstrap/governance publishes (policies x Spaces) spacelift_policy on its first apply — ~29 with
# this library and two Spaces — and iam-factory at max_vended_services = 10 creates ~50 Spaces,
# contexts and environment variables. A single 25 cap therefore blocked those roots' first apply
# every time: a guardrail whose only observed behaviour is a false positive gets switched off, which
# is how you end up with no fuse at all.
#
# Still a fuse, not an exemption. Every type below is ALSO under a tighter, purpose-built cap:
# launcher-engine-guardrail caps an engine run at 10 spacelift_stack in one Space,
# iam-factory-guardrail caps a factory run at 10 spacelift_space, and both deny outright the types
# they must never produce. Privilege objects (spacelift_role, spacelift_role_attachment,
# spacelift_user, spacelift_api_key, spacelift_idp_group_mapping, spacelift_worker_pool) are
# deliberately absent, so they stay under the stricter 25 alongside real infrastructure.
max_new_control_plane := 75

# terraform_data is here because it creates nothing at all — it is the plan-time precondition idiom
# every engine gates itself with. Counted rather than skipped so no create goes untallied.
control_plane_types := {
	"spacelift_blueprint",
	"spacelift_context",
	"spacelift_context_attachment",
	"spacelift_environment_variable",
	"spacelift_mounted_file",
	"spacelift_policy",
	"spacelift_policy_attachment",
	"spacelift_space",
	"spacelift_stack",
	"spacelift_stack_dependency",
	"spacelift_stack_dependency_reference",
	"terraform_data",
}

# Counts the create half of a replacement too: replacing 25 resources at once deserves the
# same pause as creating 25.
created := [r |
	some r in input.terraform.resource_changes
	"create" in r.change.actions
]

created_infrastructure := [r |
	some r in created
	not r.type in control_plane_types
]

created_control_plane := [r |
	some r in created
	r.type in control_plane_types
]

# The symmetric failure: a request YAML LOSING entries makes the engine destroy what it vended.
# Destroys get the same fuse as creates. A replacement counts in both directions, which is the
# same pause it already earned on the create side.
max_destroyed_resources := 25

max_destroyed_control_plane := 75

destroyed := [r |
	some r in input.terraform.resource_changes
	"delete" in r.change.actions
]

destroyed_infrastructure := [r |
	some r in destroyed
	not r.type in control_plane_types
]

destroyed_control_plane := [r |
	some r in destroyed
	r.type in control_plane_types
]

deny contains msg if {
	count(created_infrastructure) > max_new_resources
	msg := sprintf("plan creates %d infrastructure resources; cap is %d", [count(created_infrastructure), max_new_resources])
}

deny contains msg if {
	count(created_control_plane) > max_new_control_plane
	msg := sprintf("plan creates %d Spacelift control-plane objects; cap is %d", [count(created_control_plane), max_new_control_plane])
}

deny contains msg if {
	count(destroyed_infrastructure) > max_destroyed_resources
	msg := sprintf("plan destroys %d infrastructure resources; cap is %d", [count(destroyed_infrastructure), max_destroyed_resources])
}

deny contains msg if {
	count(destroyed_control_plane) > max_destroyed_control_plane
	msg := sprintf("plan destroys %d Spacelift control-plane objects; cap is %d", [count(destroyed_control_plane), max_destroyed_control_plane])
}

sample := true
