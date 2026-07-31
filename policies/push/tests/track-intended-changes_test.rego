package tests.push.track_intended_changes

import data.spacelift
import rego.v1

# `track` and `propose` are defined only by this policy, so the merged values are unambiguous.
# `ignore` is also defined by the other two push policies, so every fixture here keeps them quiet:
# a trusted author, the canonical repo owner, an approved non-draft PR, and no elevated label.
tracked(fixture) if {
	spacelift.track with input as fixture
}

proposed(fixture) if {
	spacelift.propose with input as fixture
}

ignored(fixture) if {
	spacelift.ignore with input as fixture
}

prefix(fixture) := p if {
	p := spacelift.project_prefix with input as fixture
}

project := "patterns/nonadmin-launcher/engine/app-example"

# Both taken from ignore-untrusted-authors.rego's own constants: bootstrap/governance substitutes
# them at publish time, and `opa test` merges every GIT_PUSH policy into one `ignore`, so a fixture
# that hardcoded a login would start being ignored the moment the real value changed.
trusted_login := login if {
	some login in spacelift.trusted_authors
}

owner_login := spacelift.repo_owner

stack(overrides) := json.patch(
	{
		"id": "jimmy-app-01JEXAMPLE7KXV3MNBYPSH88AX",
		"name": "jimmy-app",
		"labels": ["env:d"],
		"branch": "main",
		"namespace": "example-org",
		"repository": "platform-engineering",
		"project_root": project,
		"additional_project_globs": [],
		"administrative": false,
		"autodeploy": false,
		"state": "FINISHED",
		"terraform_version": "1.5.7",
		"worker_pool": {"public": false},
	},
	overrides,
)

push_event(branch, files, stack_overrides) := {
	"pull_request": null,
	"in_progress": [],
	"push": {
		"branch": branch,
		"affected_files": files,
		"author": trusted_login,
		"message": "change",
		"tag": "",
		"created_at": 1700000000000000000,
	},
	"stack": stack(stack_overrides),
}

pr_event(base, diff, head_files, stack_overrides) := {
	"pull_request": {
		"id": 42,
		"action": "synchronize",
		"action_initiator": trusted_login,
		"author": trusted_login,
		"head_owner": owner_login,
		"approved": true,
		"draft": false,
		"closed": false,
		"mergeable": true,
		"undiverged": true,
		"labels": [],
		"title": "change",
		"diff": diff,
		"base": {"branch": base, "affected_files": [], "author": trusted_login, "tag": ""},
		"head": {"branch": "feature", "affected_files": head_files, "author": trusted_login, "tag": ""},
	},
	"in_progress": [],
	"push": {
		"branch": "feature",
		"affected_files": head_files,
		"author": trusted_login,
		"message": "change",
		"tag": "",
	},
	"stack": stack(stack_overrides),
}

#
# Track
#

test_tracks_a_push_to_the_tracked_branch_in_project if {
	fixture := push_event("main", [sprintf("%s/main.tf", [project])], [])

	tracked(fixture)
	not ignored(fixture)
}

test_ignores_a_push_outside_the_project_root if {
	fixture := push_event("main", ["docs/WORKFLOWS.md"], [])

	not tracked(fixture)
	ignored(fixture)
}

# A bare startswith on the prefix would let root `foo` swallow the sibling `foobar/` — the
# boundary has to be the root exactly or root + "/".
test_does_not_track_a_sibling_directory_with_a_matching_prefix if {
	fixture := push_event("main", [sprintf("%s-v2/main.tf", [project])], [])

	not tracked(fixture)
	ignored(fixture)
}

# The root itself as a file path matches exactly.
test_tracks_a_file_that_is_the_project_root_path if {
	fixture := push_event("main", [project], [])

	tracked(fixture)
}

test_does_not_track_a_push_to_another_branch if {
	not tracked(push_event("feature", [sprintf("%s/main.tf", [project])], []))
}

#
# project_root is optional. Building a "<root>/" prefix from an absent value made `affected`
# permanently false, so the stack ignored every push and never ran at all.
#

test_stack_with_no_project_root_still_tracks if {
	fixture := push_event("main", ["main.tf"], [{"op": "remove", "path": "/project_root"}])

	prefix(fixture) == ""
	tracked(fixture)
	not ignored(fixture)
}

# project_root arrives as an explicit null on some stacks, which is not a string and so falls
# through to the default rather than blowing up trim().
test_stack_with_null_project_root_still_tracks if {
	fixture := push_event("main", ["main.tf"], [{
		"op": "replace",
		"path": "/project_root",
		"value": null,
	}])

	prefix(fixture) == ""
	tracked(fixture)
	not ignored(fixture)
}

test_stack_with_empty_project_root_still_tracks if {
	fixture := push_event("main", ["patterns/app-factory/main.tf"], [{
		"op": "replace",
		"path": "/project_root",
		"value": "",
	}])

	tracked(fixture)
}

test_project_root_slashes_are_normalized if {
	fixture := push_event("main", [sprintf("/%s/main.tf", [project])], [{
		"op": "replace",
		"path": "/project_root",
		"value": sprintf("/%s/", [project]),
	}])

	prefix(fixture) == project
	tracked(fixture)
}

test_additional_project_globs_are_honored if {
	fixture := push_event("main", ["modules/aws/object-storage/main.tf"], [{
		"op": "replace",
		"path": "/additional_project_globs",
		"value": ["modules/aws/**"],
	}])

	tracked(fixture)
	not ignored(fixture)
}

#
# Propose. `push` on a PR event is only the head commit, so judging a PR by push.affected_files
# ignored any PR whose relevant change landed in an earlier commit.
#

test_proposes_a_pr_whose_diff_touches_the_project if {
	fixture := pr_event("main", [sprintf("%s/main.tf", [project])], ["README.md"], [])

	spacelift.affected_pr with input as fixture
	proposed(fixture)
	not ignored(fixture)
}

test_head_commit_alone_would_have_ignored_that_pr if {
	fixture := pr_event("main", [sprintf("%s/main.tf", [project])], ["README.md"], [])

	not spacelift.affected with input as fixture
}

test_ignores_a_pr_that_touches_nothing_relevant if {
	fixture := pr_event("main", ["docs/WORKFLOWS.md"], ["docs/WORKFLOWS.md"], [])

	not proposed(fixture)
	ignored(fixture)
}

test_does_not_propose_a_pr_aimed_at_another_branch if {
	fixture := pr_event("release", [sprintf("%s/main.tf", [project])], [], [])

	not proposed(fixture)
}

test_does_not_track_an_open_pr if {
	not tracked(pr_event("main", [sprintf("%s/main.tf", [project])], [], []))
}

#
# Tags release modules, not stacks.
#

test_ignores_a_tag_push if {
	base := push_event("main", [sprintf("%s/main.tf", [project])], [])
	fixture := json.patch(base, [{"op": "replace", "path": "/push/tag", "value": "v1.2.3"}])

	ignored(fixture)
}
