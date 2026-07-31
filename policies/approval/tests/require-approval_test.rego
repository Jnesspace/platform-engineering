package tests.approval.require_approval

import data.spacelift
import rego.v1

# Assertions go through helper functions: `spacelift.foo with input as fixture == expected` parses
# the comparison into the `with` term and asserts nothing at all.
independent(fixture) if {
	spacelift.independent_approval with input as fixture
}

met(fixture) if {
	spacelift.quorum_met with input as fixture
}

prod(fixture) if {
	spacelift.is_prod with input as fixture
}

approved(fixture) if {
	spacelift.approve with input as fixture
}

rejected(fixture) if {
	spacelift.reject with input as fixture
}

owners(fixture) := o if {
	o := spacelift.run_owners with input as fixture
}

approvers(fixture) := a if {
	a := spacelift.distinct_approvers with input as fixture
}

needed(fixture) := n if {
	n := spacelift.required_approvals with input as fixture
}

review(login) := {
	"author": login,
	"session": {"login": login, "name": login, "teams": ["platform-engineering"]},
	"state": "UNCONFIRMED",
	"request": {"remote_ip": "10.0.0.1", "timestamp_ns": 1700000000000000000},
}

run(labels, approvals, rejections) := run_by(labels, approvals, rejections, null)

run_by(labels, approvals, rejections, triggered_by) := {
	"reviews": {"current": {"approvals": approvals, "rejections": rejections}, "older": []},
	"run": {
		"id": "01JEXAMPLE0RUN0FIXTURE0001",
		"state": "UNCONFIRMED",
		"type": "TRACKED",
		"branch": "main",
		"triggered_by": triggered_by,
		"creator_session": {
			"login": "alice",
			"name": "alice",
			"admin": false,
			"machine": false,
			"teams": ["platform-engineering"],
			"creator_ip": "10.0.0.1",
		},
		"drift_detection": false,
		"flags": [],
	},
	"stack": {
		"name": "app",
		"labels": labels,
		"branch": "main",
		"autodeploy": false,
		"administrative": false,
		"worker_pool": {"public": false},
	},
}

#
# Self-approval. The bug this policy exists to fix: on a push-created run triggered_by is null, so
# comparing against it alone approved anything.
#

test_blocks_self_approval_when_triggered_by_is_null if {
	fixture := run(["env:dev"], [review("alice")], [])

	owners(fixture) == {"alice"}
	not independent(fixture)
	not approved(fixture)
}

test_allows_approval_from_someone_else if {
	fixture := run(["env:dev"], [review("bob")], [])

	independent(fixture)
	approved(fixture)
}

test_blocks_self_approval_when_the_user_triggered_manually if {
	fixture := run_by(["env:dev"], [review("alice")], [], "alice")

	owners(fixture) == {"alice"}
	not independent(fixture)
	not approved(fixture)
}

# A reviewer's VCS handle and IdP login can differ; either match is self-approval.
test_blocks_self_approval_across_mismatched_handles if {
	vcs_handle := {"author": "alice-gh", "session": {"login": "alice"}, "state": "UNCONFIRMED"}
	fixture := run(["env:dev"], [vcs_handle], [])

	not independent(fixture)
	not approved(fixture)
}

#
# The regression this merge exists to prevent. Both were reachable while two APPROVAL policies were
# attached to one stack and Spacelift OR-ed them.
#

# Previously: require-prod-approval's `approve if not is_prod` fired with ZERO reviews, satisfying
# the gate deny-self-approval was holding shut.
test_non_prod_is_not_auto_approved_without_a_review if {
	fixture := run(["env:dev"], [], [])

	not prod(fixture)
	needed(fixture) == 1
	not approved(fixture)
}

# An unlabelled stack is governed exactly like a non-prod one; no label means no exemption.
test_unlabelled_stack_still_needs_an_approval if {
	fixture := run([], [], [])

	not prod(fixture)
	needed(fixture) == 1
	not approved(fixture)
}

# Previously: deny-self-approval accepted a single independent approval on prod, and the OR let
# that satisfy prod's two-approver quorum.
test_prod_is_not_approved_by_one_independent_reviewer if {
	fixture := run(["env:prod"], [review("bob")], [])

	prod(fixture)
	needed(fixture) == 2
	independent(fixture)
	not met(fixture)
	not approved(fixture)
}

#
# Fail-closed labels: an ABSENT labels key used to read as "not prod" (is_prod undefined), so a
# prod stack would have silently dropped to the one-approver bar. Unknown labels get the prod quorum.
#

test_absent_stack_labels_fail_closed_to_the_prod_quorum if {
	fixture := json.remove(run(["env:dev"], [review("bob")], []), ["/stack/labels"])

	needed(fixture) == 2
	not approved(fixture)
}

test_absent_stack_labels_still_approve_at_the_prod_quorum if {
	fixture := json.remove(run(["env:dev"], [review("bob"), review("carol")], []), ["/stack/labels"])

	needed(fixture) == 2
	approved(fixture)
}

#
# Prod quorum
#

test_two_distinct_approvers_meet_the_quorum if {
	fixture := run(["env:prod"], [review("bob"), review("carol")], [])

	prod(fixture)
	met(fixture)
	approved(fixture)
}

test_one_approver_does_not_meet_the_quorum if {
	fixture := run(["env:prod"], [review("bob")], [])

	not met(fixture)
}

# Spacelift keeps only a reviewer's newest review, but the login set makes that structural.
test_the_same_person_twice_does_not_meet_the_quorum if {
	fixture := run(["env:prod"], [review("bob"), review("bob")], [])

	approvers(fixture) == {"bob"}
	not met(fixture)
	not approved(fixture)
}

# Two approvers are not enough if both are run owners: alice created the run and bob triggered it,
# so neither review is independent even though the count is met.
test_quorum_requires_someone_other_than_the_run_owner if {
	fixture := run_by(["env:prod"], [review("alice"), review("bob")], [], "bob")

	approvers(fixture) == {"alice", "bob"}
	count(approvers(fixture)) >= 2
	not independent(fixture)
	not met(fixture)
	not approved(fixture)
}

test_quorum_met_when_the_owner_is_one_of_two if {
	fixture := run(["env:prod"], [review("alice"), review("bob")], [])

	met(fixture)
	approved(fixture)
}

test_prod_with_no_reviews_is_not_approved if {
	fixture := run(["env:prod"], [], [])

	not approved(fixture)
}

#
# Run state: the policy must not block runs a human was never meant to review.
#

test_auto_approves_a_queued_run if {
	fixture := json.patch(run(["env:dev"], [], []), [{
		"op": "replace",
		"path": "/run/state",
		"value": "QUEUED",
	}])

	not spacelift.requires_review with input as fixture
	approved(fixture)
}

test_auto_approves_a_proposed_run if {
	fixture := json.patch(run(["env:dev"], [], []), [
		{"op": "replace", "path": "/run/state", "value": "QUEUED"},
		{"op": "replace", "path": "/run/type", "value": "PROPOSED"},
	])

	approved(fixture)
}

# A queued run on prod is still not a deploy decision; the env only changes the quorum.
test_auto_approves_a_queued_prod_run if {
	fixture := json.patch(run(["env:prod"], [], []), [{
		"op": "replace",
		"path": "/run/state",
		"value": "QUEUED",
	}])

	prod(fixture)
	approved(fixture)
}

test_gates_tasks if {
	fixture := json.patch(run(["env:dev"], [], []), [
		{"op": "replace", "path": "/run/state", "value": "QUEUED"},
		{"op": "replace", "path": "/run/type", "value": "TASK"},
	])

	spacelift.requires_review with input as fixture
	not approved(fixture)
}

#
# Rejections must fail `approve` as well: approve+reject returns Undecided, not a failed run.
#

test_a_rejection_blocks_even_with_an_independent_approval if {
	fixture := run(["env:dev"], [review("bob")], [review("carol")])

	independent(fixture)
	rejected(fixture)
	not approved(fixture)
}

test_rejection_on_a_non_prod_stack_does_not_wedge_the_run if {
	fixture := run(["env:dev"], [], [review("bob")])

	rejected(fixture)
	not approved(fixture)
}

test_rejection_on_prod_blocks_a_met_quorum if {
	fixture := run(["env:prod"], [review("bob"), review("carol")], [review("dave")])

	met(fixture)
	rejected(fixture)
	not approved(fixture)
}

# A rejection on a run that needs no review must still not leave approve and reject both true.
test_rejection_on_a_queued_run_does_not_wedge_the_run if {
	fixture := json.patch(run(["env:dev"], [], [review("bob")]), [{
		"op": "replace",
		"path": "/run/state",
		"value": "QUEUED",
	}])

	rejected(fixture)
	not approved(fixture)
}

#
# Machine-created run with no login: independence is unknowable, so fall back to two reviewers.
#

test_machine_run_needs_two_reviewers if {
	fixture := json.remove(run(["env:dev"], [review("bob")], []), ["/run/creator_session/login"])

	owners(fixture) == set()
	not met(fixture)
	not approved(fixture)
}

test_machine_run_approved_by_two_reviewers if {
	fixture := json.remove(run(["env:dev"], [review("bob"), review("carol")], []), ["/run/creator_session/login"])

	owners(fixture) == set()
	approved(fixture)
}
