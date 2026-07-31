package tests.push.ignore_untrusted_authors

import data.spacelift
import rego.v1

ignored(fixture) if {
	spacelift.ignore with input as fixture
}

failed(fixture) if {
	spacelift.fail with input as fixture
}

notified(fixture) if {
	spacelift.notify with input as fixture
}

messages(fixture) := m if {
	m := spacelift.message with input as fixture
}

matched(msgs, substring) if {
	some m in msgs
	contains(m, substring)
}

project := "patterns/nonadmin-launcher/engine/app-example"

# Taken from the policy's own constants rather than written out, because bootstrap/governance
# substitutes both at publish time. The test then exercises the mechanism instead of pinning one
# account's login into the repo.
trusted_login := login if {
	some login in spacelift.trusted_authors
}

owner_login := spacelift.repo_owner

# Not labelled as an engine, so proposed-run-safety stays quiet; the PR diff touches the project
# root, so track-intended-changes does not ignore either. Any `ignore` here is this policy's.
pr(author, head_owner) := {
	"pull_request": {
		"id": 42,
		"action": "opened",
		"author": author,
		"head_owner": head_owner,
		"approved": true,
		"draft": false,
		"closed": false,
		"mergeable": true,
		"undiverged": true,
		"labels": [],
		"diff": [sprintf("%s/main.tf", [project])],
		"base": {"branch": "main"},
		"head": {"branch": "feature", "affected_files": [sprintf("%s/main.tf", [project])]},
	},
	"in_progress": [],
	"push": {
		"branch": "feature",
		"affected_files": [sprintf("%s/main.tf", [project])],
		"author": author,
		"tag": "",
	},
	"stack": {
		"id": "jimmy-app-01JEXAMPLE7KXV3MNBYPSH88AX",
		"name": "jimmy-app",
		"labels": ["env:d"],
		"branch": "main",
		"namespace": "example",
		"repository": "platform-engineering",
		"project_root": project,
		"additional_project_globs": [],
		"worker_pool": {"public": false},
	},
}

#
# Allow path
#

test_trusted_same_repo_pr_is_not_ignored if {
	fixture := pr(trusted_login, owner_login)

	spacelift.trusted_author with input as fixture
	spacelift.same_repo with input as fixture
	not ignored(fixture)
	not failed(fixture)
}

# VCS logins are case-insensitive; the original set-membership check was not.
test_author_match_is_case_insensitive if {
	fixture := pr(upper(trusted_login), upper(owner_login))

	spacelift.trusted_author with input as fixture
	spacelift.same_repo with input as fixture
	not ignored(fixture)
}

#
# Deny path
#

test_untrusted_author_is_ignored_loudly if {
	fixture := pr("driveby", owner_login)

	not spacelift.trusted_author with input as fixture
	ignored(fixture)
	notified(fixture)
	failed(fixture)
	matched(messages(fixture), "author \"driveby\" is not trusted")
}

test_fork_pr_is_ignored if {
	fixture := pr(trusted_login, "someone-else")

	not spacelift.same_repo with input as fixture
	ignored(fixture)
	matched(messages(fixture), "head branch lives in a fork")
}

test_missing_author_is_untrusted if {
	fixture := json.remove(pr(trusted_login, owner_login), ["/pull_request/author"])

	not spacelift.trusted_author with input as fixture
	ignored(fixture)
}

#
# This policy only judges pull requests; direct pushes are the other policy's business.
#

test_non_pr_push_is_untouched if {
	fixture := {
		"pull_request": null,
		"in_progress": [],
		"push": {
			"branch": "main",
			"affected_files": [sprintf("%s/main.tf", [project])],
			"author": "anyone",
			"tag": "",
		},
		"stack": {
			"id": "jimmy-app-01JEXAMPLE7KXV3MNBYPSH88AX",
			"labels": ["env:d"],
			"branch": "main",
			"namespace": "example",
			"project_root": project,
			"additional_project_globs": [],
		},
	}

	not ignored(fixture)
	not failed(fixture)
	spacelift.track with input as fixture
}

# An ABSENT pull_request key is not an explicit null: `not is_null(undefined)` is true, which
# would misread a bare push as a PR from an untrusted author and ignore it.
test_push_without_the_pull_request_key_is_untouched if {
	base := pr(trusted_login, owner_login)
	fixture := json.remove(base, ["/pull_request"])

	not spacelift.is_pr with input as fixture
	not ignored(fixture)
	not failed(fixture)
}
