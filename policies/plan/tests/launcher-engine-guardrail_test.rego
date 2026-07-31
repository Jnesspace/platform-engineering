package tests.plan.launcher_engine_guardrail

import data.spacelift
import rego.v1

denials(fixture) := msgs if {
	msgs := spacelift.deny with input as fixture
}

warnings(fixture) := msgs if {
	msgs := spacelift.warn with input as fixture
}

matched(msgs, substring) if {
	some m in msgs
	contains(m, substring)
}

team_space := "jimmy-team-01JEXAMPLE7KXV3MNBYPSH88AX"

# Shape of a stack the engine legitimately vends (patterns/nonadmin-launcher/engine/main.tf).
good_stack(name) := {
	"address": sprintf("spacelift_stack.app[%q]", [name]),
	"type": "spacelift_stack",
	"name": "app",
	"provider_name": "spacelift",
	"change": {"actions": ["create"], "after": {
		"name": name,
		"space_id": team_space,
		"repository": "platform-engineering",
		"branch": "main",
		"project_root": "patterns/nonadmin-launcher/engine/app-example",
		"labels": ["env:d", "vended-by:onboarding-engine"],
		"autodeploy": false,
		"protect_from_deletion": true,
	}},
}

engine(changes) := {
	"spacelift": {"stack": {
		"name": "onboarding-engine",
		"labels": ["poc:nonadmin-launcher", "engine"],
		"branch": "main",
		"repository": "platform-engineering",
	}},
	"terraform": {"resource_changes": changes, "terraform_version": "1.5.7"},
}

# Same plan, but on an ordinary app stack: the guardrail must stay silent.
ungoverned(changes) := {
	"spacelift": {"stack": {"name": "jimmy-app", "labels": ["env:d"]}},
	"terraform": {"resource_changes": changes},
}

#
# Allow path
#

test_allows_a_normal_vend if {
	msgs := denials(engine([good_stack("payments-api"), good_stack("payments-worker")]))
	not matched(msgs, "onboarding engine")
	not matched(msgs, "engine run")
	not matched(msgs, "vended stack")
	not matched(msgs, "provenance label")
	not matched(msgs, "privileged label")
}

test_stays_silent_on_non_engine_stacks if {
	role_grab := {
		"address": "spacelift_role_attachment.self",
		"type": "spacelift_role_attachment",
		"change": {"actions": ["create"], "after": {}},
	}

	not matched(denials(ungoverned([role_grab])), "widen its own grant")
}

#
# Deny path
#

test_denies_creating_a_role_attachment if {
	msgs := denials(engine([{
		"address": "spacelift_role_attachment.self",
		"type": "spacelift_role_attachment",
		"change": {"actions": ["create"], "after": {"role_id": "space-admin", "space_id": "root"}},
	}]))

	matched(msgs, "must not manage spacelift_role_attachment")
}

test_denies_creating_a_space if {
	msgs := denials(engine([{
		"address": "spacelift_space.new",
		"type": "spacelift_space",
		"change": {"actions": ["create"], "after": {"name": "mine", "parent_space_id": "root"}},
	}]))

	matched(msgs, "must not manage spacelift_space")
}

test_denies_an_unexpected_resource_type if {
	msgs := denials(engine([{
		"address": "aws_iam_role.sneaky",
		"type": "aws_iam_role",
		"change": {"actions": ["create"], "after": {"name": "sneaky"}},
	}]))

	matched(msgs, "not a resource type the onboarding engine produces")
}

# The engine gates itself with terraform_data.request_gate before the elevated token creates
# anything. Omitting it from the allowlist denied every single launcher run.
test_allows_the_engines_own_plan_time_gate if {
	gate := {
		"address": "terraform_data.request_gate",
		"type": "terraform_data",
		"change": {"actions": ["create"], "after": {"input": 2}},
	}
	msgs := denials(engine([gate, good_stack("payments-api")]))

	not matched(msgs, "not a resource type the onboarding engine produces")
	not matched(msgs, "must not manage")
}

# A vended stack rooted in bootstrap/ would run the root-admin bootstrap's Terraform, which
# deny-privileged-iam.rego exempts from its role-attachment deny. This is the forge that closes.
test_denies_vending_a_stack_into_the_bootstrap_layer if {
	sneaky := json.patch(good_stack("payments-api"), [{
		"op": "replace",
		"path": "/change/after/project_root",
		"value": "bootstrap/roles",
	}])

	matched(denials(engine([sneaky])), "must not vend a stack into the bootstrap/ bootstrap layer")
}

test_allows_a_normal_vended_project_root if {
	not matched(denials(engine([good_stack("payments-api")])), "bootstrap layer")
}

# Prefix matching must not fire on a directory that merely starts with the same letters.
test_does_not_confuse_a_similarly_named_project_root if {
	other := json.patch(good_stack("payments-api"), [{
		"op": "replace",
		"path": "/change/after/project_root",
		"value": "bootstrapping-guide/example",
	}])

	not matched(denials(engine([other])), "bootstrap layer")
}

test_denies_more_stacks_than_the_cap if {
	stacks := [good_stack(sprintf("app-%d", [i])) | some i in numbers.range(1, 11)]
	matched(denials(engine(stacks)), "engine run touches 11 stacks; cap is 10")
}

test_allows_exactly_the_cap if {
	stacks := [good_stack(sprintf("app-%d", [i])) | some i in numbers.range(1, 10)]
	not matched(denials(engine(stacks)), "cap is 10")
}

test_denies_spanning_two_spaces if {
	elsewhere := json.patch(good_stack("other"), [{
		"op": "replace",
		"path": "/change/after/space_id",
		"value": "some-other-space",
	}])

	matched(denials(engine([good_stack("payments-api"), elsewhere])), "may only build into one")
}

test_denies_targeting_root if {
	at_root := json.patch(good_stack("payments-api"), [{
		"op": "replace",
		"path": "/change/after/space_id",
		"value": "root",
	}])

	matched(denials(engine([at_root])), "targets the root Space")
}

test_denies_a_bad_stack_name if {
	shouty := json.patch(good_stack("payments-api"), [{
		"op": "replace",
		"path": "/change/after/name",
		"value": "Payments API!",
	}])

	matched(denials(engine([shouty])), "vended stack names must match")
}

test_denies_a_missing_provenance_label if {
	unlabelled := json.patch(good_stack("payments-api"), [{
		"op": "replace",
		"path": "/change/after/labels",
		"value": ["env:d"],
	}])

	matched(denials(engine([unlabelled])), "provenance label")
}

# Labels drive policy auto-attachment, so a vended stack must not label itself as an engine.
test_denies_claiming_an_engine_label if {
	impostor := json.patch(good_stack("payments-api"), [{
		"op": "replace",
		"path": "/change/after/labels",
		"value": ["vended-by:onboarding-engine", "engine"],
	}])

	matched(denials(engine([impostor])), "claims the privileged label \"engine\"")
}

test_denies_claiming_prod if {
	promoted := json.patch(good_stack("payments-api"), [{
		"op": "replace",
		"path": "/change/after/labels",
		"value": ["vended-by:onboarding-engine", "env:prod"],
	}])

	matched(denials(engine([promoted])), "claims the privileged label \"env:prod\"")
}

test_denies_autodeploy if {
	auto := json.patch(good_stack("payments-api"), [{
		"op": "replace",
		"path": "/change/after/autodeploy",
		"value": true,
	}])

	matched(denials(engine([auto])), "must stop at the confirm gate")
}

#
# Advisory
#

test_warns_when_deletion_protection_is_off if {
	unprotected := json.patch(good_stack("payments-api"), [{
		"op": "replace",
		"path": "/change/after/protect_from_deletion",
		"value": false,
	}])

	matched(warnings(engine([unprotected])), "without protect_from_deletion")
}

# The attribute being absent is the case OPA's `not` hoisting would silently skip.
test_warns_when_deletion_protection_is_absent if {
	stripped := json.remove(good_stack("payments-api"), ["/change/after/protect_from_deletion"])
	matched(warnings(engine([stripped])), "without protect_from_deletion")
}

test_warns_on_stack_deletion if {
	msgs := warnings(engine([{
		"address": "spacelift_stack.app[\"gone\"]",
		"type": "spacelift_stack",
		"change": {"actions": ["delete"], "before": {"name": "gone", "space_id": team_space}},
	}]))

	matched(msgs, "will be deleted")
}

test_no_warning_on_a_clean_vend if {
	not matched(warnings(engine([good_stack("payments-api")])), "protect_from_deletion")
}
