package tests.plan.iam_factory_guardrail

import data.spacelift
import rego.v1

denials(fixture) := msgs if {
	msgs := spacelift.deny with input as fixture
}

matched(msgs, substring) if {
	some m in msgs
	contains(m, substring)
}

platform_admin := "platform-admin-01JEXAMPLE7KXV3MNBYPSH88AX"

factory(changes) := {
	"spacelift": {"stack": {
		"name": "iam-factory",
		"labels": ["platform-factory"],
		"branch": "main",
		"repository": "platform-engineering",
	}},
	"terraform": {"resource_changes": changes, "terraform_version": "1.5.7"},
}

# Shapes from patterns/iam-factory/main.tf.
vended_space := {
	"address": "spacelift_space.service[\"payments\"]",
	"type": "spacelift_space",
	"provider_name": "spacelift",
	"change": {"actions": ["create"], "after": {
		"name": "payments",
		"parent_space_id": platform_admin,
		"inherit_entities": true,
	}},
}

vended_role := {
	"address": "aws_iam_role.space[\"payments\"]",
	"type": "aws_iam_role",
	"provider_name": "aws",
	"change": {"actions": ["create"], "after": {"name": "spacelift-payments"}},
}

vended_context := {
	"address": "spacelift_context.aws[\"payments\"]",
	"type": "spacelift_context",
	"provider_name": "spacelift",
	"change": {"actions": ["create"], "after": {
		"name": "aws-payments",
		"labels": ["autoattach:aws-oidc"],
	}},
}

#
# Allow path
#

test_allows_a_normal_vend if {
	msgs := denials(factory([vended_space, vended_role, vended_context]))
	not matched(msgs, "the factory must not manage")
	not matched(msgs, "not a resource type the iam-factory produces")
	not matched(msgs, "parented at")
	not matched(msgs, "vended role names must match")
	not matched(msgs, "auto-attaches on")
}

test_stays_silent_on_non_factory_stacks if {
	fixture := {
		"spacelift": {"stack": {"name": "jimmy-app", "labels": ["env:d"]}},
		"terraform": {"resource_changes": [{
			"address": "spacelift_role.mine",
			"type": "spacelift_role",
			"change": {"actions": ["create"], "after": {}},
		}]},
	}

	not matched(denials(fixture), "the factory must not manage")
}

#
# Deny path
#

test_denies_minting_a_spacelift_role if {
	msgs := denials(factory([{
		"address": "spacelift_role.mine",
		"type": "spacelift_role",
		"change": {"actions": ["create"], "after": {"name": "superuser"}},
	}]))

	matched(msgs, "the factory must not manage spacelift_role")
}

test_denies_attaching_a_policy if {
	msgs := denials(factory([{
		"address": "spacelift_policy_attachment.quiet",
		"type": "spacelift_policy_attachment",
		"change": {"actions": ["create"], "after": {}},
	}]))

	matched(msgs, "must not manage spacelift_policy_attachment")
}

test_denies_creating_a_stack if {
	msgs := denials(factory([{
		"address": "spacelift_stack.extra",
		"type": "spacelift_stack",
		"change": {"actions": ["create"], "after": {"name": "extra"}},
	}]))

	matched(msgs, "must not manage spacelift_stack")
}

test_denies_an_unexpected_resource_type if {
	msgs := denials(factory([{
		"address": "aws_s3_bucket.exfil",
		"type": "aws_s3_bucket",
		"change": {"actions": ["create"], "after": {"bucket": "exfil"}},
	}]))

	matched(msgs, "not a resource type the iam-factory produces")
}

test_denies_more_spaces_than_the_cap if {
	spaces := [json.patch(vended_space, [{
		"op": "replace",
		"path": "/address",
		"value": sprintf("spacelift_space.service[%d]", [i]),
	}]) |
		some i in numbers.range(1, 11)
	]

	matched(denials(factory(spaces)), "factory run touches 11 Spaces; cap is 10")
}

test_denies_a_space_parented_at_root if {
	at_root := json.patch(vended_space, [{
		"op": "replace",
		"path": "/change/after/parent_space_id",
		"value": "root",
	}])

	matched(denials(factory([at_root])), "is parented at root")
}

# Disabling inheritance is root-admin-only (hardening-backlog #7); the factory runs Space-admin.
test_denies_disabling_inheritance if {
	uninherited := json.patch(vended_space, [{
		"op": "replace",
		"path": "/change/after/inherit_entities",
		"value": false,
	}])

	matched(denials(factory([uninherited])), "only the root-admin bootstrap may change inheritance")
}

# Third layer over the engine's own terraform_data precondition, which a tampered engine deletes.
test_denies_an_off_pattern_role_name if {
	renamed := json.patch(vended_role, [{
		"op": "replace",
		"path": "/change/after/name",
		"value": "OrganizationAccountAccessRole",
	}])

	matched(denials(factory([renamed])), "vended role names must match")
}

# A context's autoattach label is a distribution list for its environment variables.
test_denies_a_broad_autoattach_label if {
	greedy := json.patch(vended_context, [{
		"op": "replace",
		"path": "/change/after/labels",
		"value": ["autoattach:env:prod"],
	}])

	matched(denials(factory([greedy])), "auto-attaches on \"autoattach:env:prod\"")
}

test_denies_a_foreign_oidc_audience if {
	msgs := denials(factory([{
		"address": "aws_iam_openid_connect_provider.spacelift[0]",
		"type": "aws_iam_openid_connect_provider",
		"change": {"actions": ["create"], "after": {
			"url": "https://evil.example.com",
			"client_id_list": ["evil.example.com"],
		}},
	}]))

	matched(msgs, "not a Spacelift issuer")
}

test_allows_the_real_oidc_audience if {
	msgs := denials(factory([{
		"address": "aws_iam_openid_connect_provider.spacelift[0]",
		"type": "aws_iam_openid_connect_provider",
		"change": {"actions": ["create"], "after": {
			"url": "https://example.app.spacelift.io",
			"client_id_list": ["example.app.spacelift.io"],
		}},
	}]))

	not matched(msgs, "not a Spacelift issuer")
}
