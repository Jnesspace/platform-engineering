# APPROVAL: RUN_TRIGGER and RUN_CONFIRM are split into separate consumer roles (roles/main.tf),
# but role assignment is still an account-admin act — this policy is what keeps the split honest
# at run time. One approver who is not the run owner everywhere; two on env:prod.
#
# ONE policy rather than two, because Spacelift OR-combines policies of the same type on a stack and
# two APPROVAL policies cannot be composed safely here. Verified by evaluating each of the previous
# files in isolation, as Spacelift does, and OR-ing the results:
#
#   - non-prod stack, alice self-approves her own run: deny-self-approval said undefined,
#     require-prod-approval said true (its `approve if not is_prod` rule). OR -> approved. The
#     self-approval gate was bypassed on every non-prod stack in the account.
#   - env:prod stack, ONE independent approval: deny-self-approval said true,
#     require-prod-approval said undefined. OR -> approved. The two-approver quorum was bypassed.
#
# Scoping cannot fix that: leaving deny-self-approval at "*" still lands both on prod (weakening it
# to one approver), and scoping it to env:dev/env:stage leaves every unlabelled stack with no
# APPROVAL policy at all. A gate you have to remember to label into is not a gate.
package spacelift

import rego.v1

# env:prod needs two *different* approvers. Everything else needs one, and in both cases at least
# one of them must not be the person who started the run.
min_prod_approvals := 2

min_approvals := 1

# Owner unknown (a machine session with no login): independence cannot be evaluated at all, so fall
# back to a count instead.
min_anonymous_approvals := 2

# object.get with an explicit absent-check: every other input read in this file is guarded, and
# an absent labels key must fail CLOSED — if we cannot see the labels, we cannot prove the stack
# is not prod, so it gets the prod quorum rather than the lighter one.
stack_labels := object.get(input, ["stack", "labels"], [])

stack_labels_known if is_array(object.get(input, ["stack", "labels"], null))

is_prod if "env:prod" in stack_labels

# Approval policies also run at QUEUED and PENDING_REVIEW. Without this gate every proposed run
# would park waiting for a human, so only actual deploy decisions are reviewed.
requires_review if input.run.state == "UNCONFIRMED"

requires_review if input.run.type == "TASK"

no_rejections if count(input.reviews.current.rejections) == 0

# `triggered_by` is null for runs created by a git push, so on its own it identifies nobody.
# `creator_session.login` is the field that always names the human.
run_owners := {handle |
	some handle in [
		object.get(input, ["run", "creator_session", "login"], null),
		object.get(input, ["run", "triggered_by"], null),
	]
	is_string(handle)
}

# A reviewer's VCS handle and IdP login can differ; either one matching is self-approval.
reviewer_handles(review) := {handle |
	some handle in [
		object.get(review, "author", null),
		object.get(review, ["session", "login"], null),
	]
	is_string(handle)
}

# Keyed by login so one person re-reviewing cannot satisfy the quorum alone.
distinct_approvers := {login |
	some approval in input.reviews.current.approvals
	login := object.get(approval, ["session", "login"], object.get(approval, "author", ""))
	login != ""
}

independent_approval if {
	some approval in input.reviews.current.approvals
	count(reviewer_handles(approval) & run_owners) == 0
}

# Default is the prod quorum: prod, or labels unknown, both land here. Only a stack whose
# labels are present AND lack env:prod earns the lighter bar. (The literal repeats
# min_prod_approvals because a default rule's value cannot reference a variable.)
default required_approvals := 2

required_approvals := min_approvals if {
	not is_prod
	stack_labels_known
}

quorum_met if {
	count(run_owners) > 0
	count(distinct_approvers) >= required_approvals
	independent_approval
}

quorum_met if {
	count(run_owners) == 0
	count(distinct_approvers) >= min_anonymous_approvals
}

approve if {
	not requires_review
	no_rejections
}

approve if {
	requires_review
	quorum_met
	no_rejections
}

# `no_rejections` on both approve rules is what makes this bite: when approve and reject are both
# true Spacelift returns Undecided, which wedges the run instead of failing it.
reject if count(input.reviews.current.rejections) > 0

sample := true
