package tests.plan.deny_privileged_iam

import data.spacelift
import rego.v1

denials(fixture) := msgs if {
	msgs := spacelift.deny with input as fixture
}

matched(msgs, substring) if {
	some m in msgs
	contains(m, substring)
}

plan(changes) := {"terraform": {"resource_changes": changes}}

# A stack's project_root as the CONTROL PLANE holds it — not run.runtime_config.project_root, which
# .spacelift/config.yml can override.
on_stack(project_root, labels, changes) := {
	"spacelift": {"stack": {
		"name": "governance",
		"project_root": project_root,
		"labels": labels,
		"repository": "platform-engineering",
	}},
	"terraform": {"resource_changes": changes},
}

role_attachment := {
	"address": "spacelift_role_attachment.engine",
	"type": "spacelift_role_attachment",
	"change": {"actions": ["create"], "after": {"role_id": "space-admin"}},
}

test_denies_creating_a_role_attachment if {
	msgs := denials(plan([{
		"address": "spacelift_role_attachment.self",
		"type": "spacelift_role_attachment",
		"change": {"actions": ["create"], "after": {"role_id": "space-admin"}},
	}]))

	matched(msgs, "create spacelift_role_attachment")
}

# Repointing an existing attachment is the same escalation as creating one.
test_denies_updating_a_role_attachment if {
	msgs := denials(plan([{
		"address": "spacelift_role_attachment.self",
		"type": "spacelift_role_attachment",
		"change": {"actions": ["update"], "before": {"space_id": "team"}, "after": {"space_id": "root"}},
	}]))

	matched(msgs, "update spacelift_role_attachment")
}

test_denies_creating_a_static_access_key if {
	msgs := denials(plan([{
		"address": "aws_iam_access_key.ci",
		"type": "aws_iam_access_key",
		"change": {"actions": ["create"], "after": {"user": "ci"}},
	}]))

	matched(msgs, "use an OIDC-federated role")
}

test_allows_an_oidc_role if {
	msgs := denials(plan([{
		"address": "aws_iam_role.app",
		"type": "aws_iam_role",
		"change": {"actions": ["create"], "after": {"name": "jimmy-app"}},
	}]))

	not matched(msgs, "is blocked")
}

# Deleting a long-lived key is cleanup, not escalation.
test_allows_deleting_an_access_key if {
	msgs := denials(plan([{
		"address": "aws_iam_access_key.ci",
		"type": "aws_iam_access_key",
		"change": {"actions": ["delete"], "before": {"user": "ci"}},
	}]))

	not matched(msgs, "is blocked")
}

#
# The bootstrap boundary. Minting elevation is the bootstrap layer's job and nobody else's, so the
# exemption has to be something an engine cannot claim.
#

test_allows_the_bootstrap_layer_to_mint_a_role_attachment if {
	msgs := denials(on_stack("bootstrap/roles", ["elevated"], [role_attachment]))

	spacelift.bootstrap_layer_run with input as on_stack("bootstrap/roles", ["elevated"], [role_attachment])
	not matched(msgs, "is blocked")
}

test_allows_the_governance_root_to_manage_its_own_plane if {
	msgs := denials(on_stack("bootstrap/governance", [], [
		role_attachment,
		{
			"address": "spacelift_policy.governed[\"plan/cap-new-resources\"]",
			"type": "spacelift_policy",
			"change": {"actions": ["create"], "after": {"type": "PLAN"}},
		},
	]))

	not matched(msgs, "is blocked")
}

# An engine is denied even from a bootstrap/ path: labels only ever REVOKE the exemption, so the
# one thing an engine can influence about itself cannot buy it privilege.
test_an_engine_label_revokes_the_exemption if {
	fixture := on_stack("bootstrap/roles", ["engine", "poc:nonadmin-launcher"], [role_attachment])

	not spacelift.bootstrap_layer_run with input as fixture
	matched(denials(fixture), "create spacelift_role_attachment")
}

test_the_factory_label_revokes_the_exemption if {
	matched(
		denials(on_stack("bootstrap/iam-factory", ["platform-factory"], [role_attachment])),
		"create spacelift_role_attachment",
	)
}

test_denies_an_engine_at_its_real_project_root if {
	matched(
		denials(on_stack("patterns/nonadmin-launcher/engine", ["engine"], [role_attachment])),
		"create spacelift_role_attachment",
	)
}

# runtime_config.project_root comes from .spacelift/config.yml, which proposed-run-safety.rego
# already treats as a plan-time RCE path. Only the stack setting counts.
test_a_forged_runtime_project_root_does_not_grant_the_exemption if {
	base := on_stack("patterns/nonadmin-launcher/engine", ["engine"], [role_attachment])
	fixture := json.patch(base, [{
		"op": "add",
		"path": "/spacelift/run",
		"value": {"runtime_config": {"project_root": "bootstrap/roles"}},
	}])

	not spacelift.bootstrap_layer_run with input as fixture
	matched(denials(fixture), "create spacelift_role_attachment")
}

# An absent project_root must leave the exemption undefined, not true. This is the `not` hoisting
# trap: get it wrong and every stack in the account becomes exempt.
test_a_missing_project_root_fails_closed if {
	fixture := {
		"spacelift": {"stack": {"name": "mystery", "labels": []}},
		"terraform": {"resource_changes": [role_attachment]},
	}

	not spacelift.bootstrap_layer_run with input as fixture
	matched(denials(fixture), "create spacelift_role_attachment")
}

test_a_non_string_project_root_fails_closed if {
	matched(denials(on_stack(null, [], [role_attachment])), "create spacelift_role_attachment")
}

# Prefix matching must not fire on a path that merely starts with the same letters.
test_a_similarly_named_project_root_is_not_the_bootstrap_layer if {
	matched(
		denials(on_stack("bootstrapping-guide/example", [], [role_attachment])),
		"create spacelift_role_attachment",
	)
}

# The exemption covers Spacelift grants only. Nothing in this repo, bootstrap included, has any
# business minting a long-lived AWS credential.
test_the_bootstrap_layer_still_may_not_mint_a_static_key if {
	msgs := denials(on_stack("bootstrap/roles", [], [{
		"address": "aws_iam_access_key.ci",
		"type": "aws_iam_access_key",
		"change": {"actions": ["create"], "after": {"user": "ci"}},
	}]))

	matched(msgs, "use an OIDC-federated role")
}

#
# IAM document inspection: blocking resource types leaves policy CONTENT unchecked, so an
# ordinary stack with iam:* in its runtime role could mint privilege inline.
#

policy_with_statements(type, statements) := {
	"address": sprintf("%s.app", [type]),
	"type": type,
	"change": {"actions": ["create"], "after": {
		"name": "app",
		"policy": json.marshal({"Version": "2012-10-17", "Statement": statements}),
	}},
}

test_denies_a_wildcard_action_grant if {
	msgs := denials(plan([policy_with_statements("aws_iam_role_policy", [
		{"Effect": "Allow", "Action": "*", "Resource": "*"},
	])]))

	matched(msgs, "grants Action \"*\"")
}

test_denies_a_wildcard_action_in_a_managed_policy if {
	msgs := denials(plan([policy_with_statements("aws_iam_policy", [
		{"Effect": "Allow", "Action": ["s3:GetObject", "*"], "Resource": "arn:aws:s3:::app/*"},
	])]))

	matched(msgs, "grants Action \"*\"")
}

test_denies_notaction_in_a_document if {
	msgs := denials(plan([policy_with_statements("aws_iam_role_policy", [
		{"Effect": "Allow", "NotAction": "iam:DeleteRole", "Resource": "*"},
	])]))

	matched(msgs, "uses NotAction")
}

test_denies_an_unpinned_passrole if {
	msgs := denials(plan([policy_with_statements("aws_iam_role_policy", [
		{"Effect": "Allow", "Action": "iam:PassRole", "Resource": "*"},
	])]))

	matched(msgs, "iam:PassRole on \"*\"")
}

test_allows_a_pinned_passrole if {
	msgs := denials(plan([policy_with_statements("aws_iam_role_policy", [
		{"Effect": "Allow", "Action": "iam:PassRole", "Resource": "arn:aws:iam::111122223333:role/app-runner"},
	])]))

	not matched(msgs, "iam:PassRole")
}

test_allows_an_enumerated_least_privilege_grant if {
	msgs := denials(plan([policy_with_statements("aws_iam_role_policy", [
		{"Effect": "Allow", "Action": ["s3:GetObject", "s3:PutObject"], "Resource": "arn:aws:s3:::app/*"},
		{"Effect": "Deny", "Action": "*", "Resource": "*"},
	])]))

	not matched(msgs, "grants Action")
	not matched(msgs, "NotAction")
}

# Policies embedding unknown ARNs are absent from `after` on a first plan — say so, like the
# trust-boundary policy does for its own unknowns.
test_warns_when_the_policy_document_is_unknown if {
	doc := {
		"address": "aws_iam_role_policy.app",
		"type": "aws_iam_role_policy",
		"change": {"actions": ["create"], "after": {"name": "app"}},
	}

	matched(warnings(plan([doc])), "could not be inspected")
}

warnings(fixture) := msgs if {
	msgs := spacelift.warn with input as fixture
}

# The factory's own documents are the trust-boundary policy's job (its boundary is Allow-* by
# design); this policy must not double-report them.
test_exempts_the_factory_stack_from_document_inspection if {
	msgs := denials(on_stack("patterns/iam-factory", ["platform-factory"], [
		policy_with_statements("aws_iam_policy", [{"Effect": "Allow", "Action": "*", "Resource": "*"}]),
	]))

	not matched(msgs, "grants Action")
}
