package tests.push.proposed_run_safety

import data.spacelift
import rego.v1

ignored(fixture) if {
	spacelift.ignore with input as fixture
}

failed(fixture) if {
	spacelift.fail with input as fixture
}

messages(fixture) := m if {
	m := spacelift.message with input as fixture
}

matched(msgs, substring) if {
	some m in msgs
	contains(m, substring)
}

engine_project := "patterns/nonadmin-launcher/engine"

# Both taken from ignore-untrusted-authors.rego's own constants: bootstrap/governance substitutes
# them at publish time, and `opa test` merges every GIT_PUSH policy into one `ignore`, so a fixture
# that hardcoded a login would start being ignored the moment the real value changed.
trusted_login := login if {
	some login in spacelift.trusted_authors
}

owner_login := spacelift.repo_owner

# Trusted author on the canonical repo, and a diff inside the project root, so neither
# ignore-untrusted-authors nor track-intended-changes ignores. Any `ignore` here is this policy's.
pr(labels, diff, overrides) := json.patch(
	{
		"pull_request": {
			"id": 42,
			"action": "synchronize",
			"author": trusted_login,
			"head_owner": owner_login,
			"approved": true,
			"draft": false,
			"closed": false,
			"mergeable": true,
			"undiverged": true,
			"labels": [],
			"diff": diff,
			"base": {"branch": "main"},
			"head": {"branch": "feature", "affected_files": diff},
		},
		"in_progress": [],
		"push": {"branch": "feature", "affected_files": diff, "author": trusted_login, "tag": ""},
		"stack": {
			"id": "onboarding-engine-01JEXAMPLE7KXV3MNBYPSH88AX",
			"name": "onboarding-engine",
			"labels": labels,
			"branch": "main",
			"namespace": "example-org",
			"repository": "platform-engineering",
			"project_root": engine_project,
			"additional_project_globs": [],
			"worker_pool": {"public": false},
		},
	},
	overrides,
)

engine_labels := ["poc:nonadmin-launcher", "engine"]

ordinary_labels := ["env:d"]

normal_diff := [sprintf("%s/requests/payments.yaml", [engine_project])]

#
# Allow path: a reviewed PR that only changes request data still gets its proposed run.
#

test_reviewed_data_only_pr_still_runs if {
	fixture := pr(engine_labels, normal_diff, [])

	spacelift.elevated with input as fixture
	spacelift.reviewed with input as fixture
	not spacelift.touches_run_config with input as fixture
	not ignored(fixture)
	spacelift.propose with input as fixture
}

# The gate is scoped to elevated stacks; ordinary app stacks keep the normal PR flow.
test_ordinary_stack_is_unaffected_by_an_unapproved_pr if {
	fixture := pr(ordinary_labels, normal_diff, [{
		"op": "replace",
		"path": "/pull_request/approved",
		"value": false,
	}])

	not spacelift.elevated with input as fixture
	not ignored(fixture)
}

test_non_pr_push_to_an_elevated_stack_is_unaffected if {
	fixture := {
		"pull_request": null,
		"in_progress": [],
		"push": {"branch": "main", "affected_files": normal_diff, "author": trusted_login, "tag": ""},
		"stack": {
			"id": "onboarding-engine-01JEXAMPLE7KXV3MNBYPSH88AX",
			"labels": engine_labels,
			"branch": "main",
			"namespace": "example-org",
			"project_root": engine_project,
			"additional_project_globs": [],
		},
	}

	not ignored(fixture)
	spacelift.track with input as fixture
}

# An ABSENT pull_request key is not the same as an explicit null: `not is_null(undefined)` is
# true, which would misread a bare push as a PR and silently drop tracked-branch pushes.
test_push_event_without_the_pull_request_key_is_unaffected if {
	fixture := {
		"in_progress": [],
		"push": {"branch": "main", "affected_files": normal_diff, "author": trusted_login, "tag": ""},
		"stack": {
			"id": "onboarding-engine-01JEXAMPLE7KXV3MNBYPSH88AX",
			"labels": engine_labels,
			"branch": "main",
			"namespace": "example-org",
			"project_root": engine_project,
			"additional_project_globs": [],
		},
	}

	not spacelift.is_pr with input as fixture
	not ignored(fixture)
	spacelift.track with input as fixture
}

#
# Deny path: unreviewed code must never reach the elevated token.
#

test_unapproved_pr_gets_no_proposed_run if {
	fixture := pr(engine_labels, normal_diff, [{
		"op": "replace",
		"path": "/pull_request/approved",
		"value": false,
	}])

	not spacelift.reviewed with input as fixture
	ignored(fixture)
	failed(fixture)
	matched(messages(fixture), "draft or not approved")
}

test_draft_pr_gets_no_proposed_run if {
	fixture := pr(engine_labels, normal_diff, [{
		"op": "replace",
		"path": "/pull_request/draft",
		"value": true,
	}])

	not spacelift.reviewed with input as fixture
	ignored(fixture)
}

#
# Deny path: run-execution config is blocked even when the PR is approved, because the hook fires
# before any PLAN policy can see it.
#

test_spacelift_config_change_is_blocked_even_when_approved if {
	fixture := pr(engine_labels, array.concat(normal_diff, [".spacelift/config.yml"]), [])

	spacelift.reviewed with input as fixture
	spacelift.touches_run_config with input as fixture
	ignored(fixture)
	matched(messages(fixture), "edits run execution config")
}

test_leading_slash_does_not_evade_the_config_check if {
	fixture := pr(engine_labels, ["/.spacelift/config.yml"], [])

	spacelift.touches_run_config with input as fixture
	ignored(fixture)
}

# *.custom.spacelift.json is merged into the PLAN policy input, so editing it poisons the
# guardrail that is supposed to catch everything else.
test_custom_plan_policy_input_change_is_blocked if {
	fixture := pr(engine_labels, [sprintf("%s/tfsec.custom.spacelift.json", [engine_project])], [])

	spacelift.touches_run_config with input as fixture
	ignored(fixture)
}

test_ordinary_stack_may_change_run_config_by_pr if {
	fixture := pr(ordinary_labels, array.concat(normal_diff, [".spacelift/config.yml"]), [])

	not spacelift.elevated with input as fixture
	not ignored(fixture)
}
