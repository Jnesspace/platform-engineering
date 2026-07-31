# GIT_PUSH: a proposed run executes PR-authored code with the stack's credentials, so only vetted authors on the canonical repo get one. Restrictive by design — it only ever ignores, never grants, because Spacelift ignores a push if ANY attached policy says ignore. Pair it with track-intended-changes.rego, which supplies track/propose.
package spacelift

import rego.v1

# Both constants are account-specific, so they are placeholders here and bootstrap/governance
# substitutes the real values at publish time from var.trusted_pr_authors / var.repo_owner. They
# stay ordinary Rego string literals — shaped like what replaces them — so `opa test policies/`
# runs this file standalone, and an unsubstituted copy fails CLOSED: no login matches, so every
# pull request is ignored rather than trusted. The governance root refuses to publish one anyway.
#
# Logins are compared case-insensitively; keep these lowercase.
trusted_authors := {"replace-with-trusted-authors"}

# Owner of the canonical repository. Spacelift's stack.namespace is documented as "only relevant to
# GitLab repositories", so it is empty on GitHub and cannot be compared against — the owner has to
# be pinned here.
repo_owner := "replace-with-repo-owner"

# is_object, not `not is_null`: an ABSENT pull_request key makes `not is_null(...)` true
# (negation of undefined), which would misread a bare push event as a PR.
is_pr if is_object(input.pull_request)

pr_author := lower(object.get(input, ["pull_request", "author"], ""))

pr_head_owner := lower(object.get(input, ["pull_request", "head_owner"], ""))

trusted_author if pr_author in trusted_authors

same_repo if pr_head_owner == repo_owner

# No `allow_fork` rule anywhere in this library: without one, Spacelift refuses to run
# forked pull requests at all. This is the belt to that braces.
ignore if {
	is_pr
	not same_repo
}

ignore if {
	is_pr
	not trusted_author
}

# A silently skipped check reads as "nothing to do" on the PR. Make it visible and red.
notify if ignore

fail if ignore

message contains sprintf("Spacelift ignored this pull request: author %q is not trusted for this stack.", [pr_author]) if {
	is_pr
	not trusted_author
}

message contains "Spacelift ignored this pull request: its head branch lives in a fork." if {
	is_pr
	not same_repo
}

sample := true
