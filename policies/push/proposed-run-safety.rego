# GIT_PUSH (hardening-backlog #3): a proposed run on an elevated engine executes PR-authored plan-time code — .spacelift/config.yml before_init hooks, external data sources, provider plugins — with the engine's admin token. That is remote code execution wearing an "it's only a plan" hat. This withholds the proposed run when the PR is unreviewed or rewrites how the run itself executes. Restrictive only: it never grants track/propose.
package spacelift

import rego.v1

# Labels carried by the stacks whose runs get an elevated token (see bootstrap/). This set must
# cover every label another policy treats as privileged — launcher-engine-guardrail gates on
# poc:nonadmin-launcher and deny-privileged-iam disqualifies app-factory — or those stacks run
# PR-authored code with an admin token and no review gate. The consistency test in
# policies/plan/tests/ asserts the superset.
elevated_labels := {"engine", "poc:nonadmin-launcher", "platform-factory", "app-factory", "elevated"}

# Files that change how a run executes rather than what it plans. `.spacelift/config.yml`
# carries before_init; `*.custom.spacelift.json` is merged into the PLAN policy input, so
# editing it poisons the very guardrail meant to catch this.
run_config_prefixes := {".spacelift/"}

run_config_suffixes := {".custom.spacelift.json"}

elevated if {
	some label in input.stack.labels
	label in elevated_labels
}

# is_object, not `not is_null`: an ABSENT pull_request key makes `not is_null(...)` true
# (negation of undefined), which would misread a bare push event as a PR.
is_pr if is_object(input.pull_request)

pr_files := object.get(input, ["pull_request", "diff"], [])

touches_run_config if {
	some path in pr_files
	some prefix in run_config_prefixes
	startswith(trim(path, "/"), prefix)
}

touches_run_config if {
	some path in pr_files
	some suffix in run_config_suffixes
	endswith(path, suffix)
}

reviewed if {
	input.pull_request.approved
	not input.pull_request.draft
}

# Unreviewed PR code must never reach an elevated token.
ignore if {
	elevated
	is_pr
	not reviewed
}

# An approved PR still gets nothing when it rewrites the run's own execution config: the
# hook fires before any PLAN policy can see it, and the reviewer approved a diff, not a
# new hook chain. Land it on the tracked branch, where branch protection applies.
ignore if {
	elevated
	is_pr
	touches_run_config
}

notify if ignore

fail if ignore

message contains "Spacelift withheld the proposed run: this stack runs with elevated credentials, and the pull request is a draft or not approved." if {
	elevated
	is_pr
	not reviewed
}

message contains "Spacelift withheld the proposed run: this pull request edits run execution config (.spacelift/ or *.custom.spacelift.json). Merge it on the tracked branch instead." if {
	elevated
	is_pr
	touches_run_config
}

sample := true
