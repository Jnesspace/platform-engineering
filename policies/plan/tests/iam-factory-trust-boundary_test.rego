package tests.plan.iam_factory_trust_boundary

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

issuer := "example.app.spacelift.io"

space_id := "payments-01JEXAMPLE7KXV3MNBYPSH88AX"

boundary_arn := "arn:aws:iam::111122223333:policy/spacelift-space-boundary"

oidc_arn := "arn:aws:iam::111122223333:oidc-provider/example.app.spacelift.io"

factory(changes) := {
	"spacelift": {"stack": {"name": "iam-factory", "labels": ["platform-factory"]}},
	"terraform": {"resource_changes": changes, "terraform_version": "1.5.7"},
}

# The trust policy patterns/iam-factory/main.tf actually renders, once the Space ID is known.
good_trust := {
	"Version": "2012-10-17",
	"Statement": [{
		"Effect": "Allow",
		"Action": "sts:AssumeRoleWithWebIdentity",
		"Principal": {"Federated": oidc_arn},
		"Condition": {
			"StringEquals": {sprintf("%s:aud", [issuer]): issuer},
			"StringLike": {sprintf("%s:sub", [issuer]): [
				sprintf("space:%s:*:scope:write", [space_id]),
				sprintf("space:%s:*:scope:read", [space_id]),
			]},
		},
	}],
}

role_with_trust(trust) := {
	"address": "aws_iam_role.space[\"payments\"]",
	"type": "aws_iam_role",
	"provider_name": "aws",
	"change": {"actions": ["create"], "after": {
		"name": "spacelift-payments",
		"permissions_boundary": boundary_arn,
		"assume_role_policy": json.marshal(trust),
	}},
}

role_policy(actions) := {
	"address": "aws_iam_role_policy.space[\"payments\"]",
	"type": "aws_iam_role_policy",
	"provider_name": "aws",
	"change": {"actions": ["create"], "after": {
		"name": "spacelift-payments-scoped",
		"policy": json.marshal({"Version": "2012-10-17", "Statement": [
			{"Sid": "CatalogGrant", "Effect": "Allow", "Action": actions, "Resource": "*"},
			{"Sid": "ProviderBaseline", "Effect": "Allow", "Action": ["sts:GetCallerIdentity"], "Resource": "*"},
		]}),
	}},
}

boundary_policy(statements) := {
	"address": "aws_iam_policy.boundary",
	"type": "aws_iam_policy",
	"provider_name": "aws",
	"change": {"actions": ["create"], "after": {
		"name": "spacelift-space-boundary",
		"policy": json.marshal({"Version": "2012-10-17", "Statement": statements}),
	}},
}

good_boundary_statements := [
	{"Sid": "AllowEverythingByDefault", "Effect": "Allow", "Action": "*", "Resource": "*"},
	{
		"Sid": "DenyPrivilegeEscalationAndControlPlane",
		"Effect": "Deny",
		"Action": ["iam:*", "organizations:*", "account:*", "sts:AssumeRole", "sts:AssumeRoleWithSAML"],
		"Resource": "*",
	},
]

#
# Allow path: an untampered factory run must produce nothing.
#

test_allows_an_untampered_vend if {
	msgs := denials(factory([
		role_with_trust(good_trust),
		role_policy(["s3:GetObject", "s3:PutObject", "s3:ListBucket"]),
		boundary_policy(good_boundary_statements),
	]))

	not matched(msgs, "boundary")
	not matched(msgs, "trusts")
	not matched(msgs, ":sub")
	not matched(msgs, "grants")
	not matched(msgs, "NotAction")
	not matched(msgs, "Federated")
}

test_stays_silent_on_non_factory_stacks if {
	fixture := {
		"spacelift": {"stack": {"name": "jimmy-app", "labels": ["env:d"]}},
		"terraform": {"resource_changes": [role_policy(["iam:CreateUser"])]},
	}

	not matched(denials(fixture), "off-catalog")
}

#
# Permissions boundary
#

test_denies_a_substituted_boundary if {
	swapped := json.patch(role_with_trust(good_trust), [{
		"op": "replace",
		"path": "/change/after/permissions_boundary",
		"value": "arn:aws:iam::111122223333:policy/AllowEverything",
	}])

	matched(denials(factory([swapped])), "instead of one ending in")
}

# Unknown at plan time on the first apply, so advisory rather than blocking.
test_warns_when_the_boundary_is_absent if {
	detached := json.remove(role_with_trust(good_trust), ["/change/after/permissions_boundary"])
	msgs := warnings(factory([detached]))

	matched(msgs, "no permissions_boundary in the plan")
	not matched(denials(factory([detached])), "instead of one ending in")
}

test_denies_weakening_the_boundary if {
	weakened := [
		{"Sid": "AllowEverythingByDefault", "Effect": "Allow", "Action": "*", "Resource": "*"},
		{"Sid": "Deny", "Effect": "Deny", "Action": ["organizations:*", "account:*"], "Resource": "*"},
	]

	matched(denials(factory([boundary_policy(weakened)])), "no longer unconditionally denies [\"iam:*\"]")
}

# An absent `after` boundary is only a first-apply unknown when `before` was absent too. If the
# role HAD the boundary, dropping it is a detach and must deny, not warn.
test_denies_detaching_an_existing_boundary if {
	detached := json.remove(role_with_trust(good_trust), ["/change/after/permissions_boundary"])
	with_before := json.patch(detached, [
		{"op": "replace", "path": "/change/actions", "value": ["update"]},
		{"op": "add", "path": "/change/before", "value": {"permissions_boundary": boundary_arn}},
	])

	matched(denials(factory([with_before])), "removes permissions_boundary")
	not matched(warnings(factory([with_before])), "no permissions_boundary in the plan")
}

# A Deny behind a condition — impossible or not — names the right actions and stops nothing.
test_a_conditioned_boundary_deny_is_not_coverage if {
	conditioned := [
		{"Sid": "AllowEverythingByDefault", "Effect": "Allow", "Action": "*", "Resource": "*"},
		{
			"Sid": "DenyPrivilegeEscalationAndControlPlane",
			"Effect": "Deny",
			"Action": ["iam:*", "organizations:*", "account:*"],
			"Resource": "*",
			"Condition": {"Null": {"aws:PrincipalTag/team": "false"}},
		},
	]

	matched(denials(factory([boundary_policy(conditioned)])), "no longer unconditionally denies")
}

# Same for a deny scoped to an irrelevant resource: coverage in name only.
test_a_resource_scoped_boundary_deny_is_not_coverage if {
	scoped := [
		{"Sid": "AllowEverythingByDefault", "Effect": "Allow", "Action": "*", "Resource": "*"},
		{
			"Sid": "DenyPrivilegeEscalationAndControlPlane",
			"Effect": "Deny",
			"Action": ["iam:*", "organizations:*", "account:*"],
			"Resource": "arn:aws:s3:::only-this-bucket/*",
		},
	]

	matched(denials(factory([boundary_policy(scoped)])), "no longer unconditionally denies")
}

test_denies_removing_the_boundary_deny_entirely if {
	toothless := [{"Sid": "Allow", "Effect": "Allow", "Action": "*", "Resource": "*"}]
	matched(denials(factory([boundary_policy(toothless)])), "weakens the permissions boundary")
}

#
# OIDC trust policy
#

# The whole point of the factory: a role reachable only from its own Space.
test_denies_a_wildcard_space_in_sub if {
	wildcard := json.patch(good_trust, [{
		"op": "replace",
		"path": "/Statement/0/Condition/StringLike",
		"value": {sprintf("%s:sub", [issuer]): "space:*:*:scope:write"},
	}])

	matched(denials(factory([role_with_trust(wildcard)])), "not pinned to a single Space")
}

test_denies_a_bare_wildcard_sub if {
	anything := json.patch(good_trust, [{
		"op": "replace",
		"path": "/Statement/0/Condition/StringLike",
		"value": {sprintf("%s:sub", [issuer]): "*"},
	}])

	matched(denials(factory([role_with_trust(anything)])), "not pinned to a single Space")
}

test_denies_a_trust_policy_with_no_sub_condition if {
	aud_only := json.patch(good_trust, [{
		"op": "replace",
		"path": "/Statement/0/Condition",
		"value": {"StringEquals": {sprintf("%s:aud", [issuer]): issuer}},
	}])

	matched(denials(factory([role_with_trust(aud_only)])), "not pinned to a Space")
}

test_denies_a_non_oidc_principal if {
	account_trust := {"Version": "2012-10-17", "Statement": [{
		"Effect": "Allow",
		"Action": "sts:AssumeRole",
		"Principal": {"AWS": "arn:aws:iam::999999999999:root"},
	}]}

	msgs := denials(factory([role_with_trust(account_trust)]))
	matched(msgs, "no Federated principal")
	matched(msgs, "may only be assumed via sts:AssumeRoleWithWebIdentity")
}

# A Space-shaped sub means nothing when the issuer is a foreign IdP: anyone who can create an
# OIDC provider in the account can mint that sub themselves.
test_denies_a_foreign_oidc_provider if {
	foreign := json.patch(good_trust, [
		{"op": "replace", "path": "/Statement/0/Principal/Federated", "value": "arn:aws:iam::111122223333:oidc-provider/token.actions.githubusercontent.com"},
	])

	matched(denials(factory([role_with_trust(foreign)])), "not the Spacelift account endpoint")
}

# Without an aud condition the role accepts tokens minted for ANY audience of the same issuer.
test_denies_a_missing_aud_condition if {
	sub_only := json.patch(good_trust, [{
		"op": "replace",
		"path": "/Statement/0/Condition",
		"value": {"StringLike": {sprintf("%s:sub", [issuer]): [sprintf("space:%s:*:scope:write", [space_id])]}},
	}])

	matched(denials(factory([role_with_trust(sub_only)])), "no `:aud` condition")
}

test_denies_a_foreign_audience if {
	foreign_aud := json.patch(good_trust, [{
		"op": "replace",
		"path": "/Statement/0/Condition/StringEquals",
		"value": {sprintf("%s:aud", [issuer]): "sts.amazonaws.com"},
	}])

	matched(denials(factory([role_with_trust(foreign_aud)])), "trusts aud")
}

test_denies_an_extra_assume_action if {
	widened := json.patch(good_trust, [{
		"op": "replace",
		"path": "/Statement/0/Action",
		"value": ["sts:AssumeRoleWithWebIdentity", "sts:TagSession"],
	}])

	matched(denials(factory([role_with_trust(widened)])), "may only be assumed via")
}

# A new Space means the Space ID, and therefore the whole document, is unknown at plan time.
test_warns_when_the_trust_policy_is_unknown if {
	unknown := json.remove(role_with_trust(good_trust), ["/change/after/assume_role_policy"])
	matched(warnings(factory([unknown])), "its Space pin could not be verified")
}

#
# Inline grant
#

test_denies_an_off_catalog_iam_grant if {
	matched(denials(factory([role_policy(["s3:GetObject", "iam:PassRole"])])), "off-catalog")
}

test_denies_a_full_wildcard_grant if {
	matched(denials(factory([role_policy("*")])), "off-catalog")
}

test_denies_an_sts_assume_role_grant if {
	matched(denials(factory([role_policy(["sts:AssumeRole"])])), "off-catalog")
}

test_denies_an_organizations_grant if {
	matched(denials(factory([role_policy(["organizations:ListAccounts"])])), "off-catalog")
}

test_allows_the_provider_baseline if {
	not matched(denials(factory([role_policy(["s3:GetObject"])])), "off-catalog")
}

# NotAction inverts an allow into "everything except", the usual way past an action allowlist.
test_denies_notaction if {
	inverted := {
		"address": "aws_iam_role_policy.space[\"payments\"]",
		"type": "aws_iam_role_policy",
		"change": {"actions": ["create"], "after": {
			"name": "spacelift-payments-scoped",
			"policy": json.marshal({"Version": "2012-10-17", "Statement": [{
				"Effect": "Allow",
				"NotAction": "iam:DeleteRole",
				"Resource": "*",
			}]}),
		}},
	}

	matched(denials(factory([inverted])), "uses NotAction")
}
