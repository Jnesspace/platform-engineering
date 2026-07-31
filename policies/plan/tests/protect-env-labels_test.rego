package tests.plan.protect_env_labels

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

stack_update(before_labels, after_labels) := {"terraform": {"resource_changes": [{
	"address": "spacelift_stack.env",
	"type": "spacelift_stack",
	"change": {
		"actions": ["update"],
		"before": {"name": "app-prod", "labels": before_labels},
		"after": {"name": "app-prod", "labels": after_labels},
	},
}]}}

test_denies_promoting_a_lane if {
	msgs := denials(stack_update(["env:dev", "app-factory"], ["env:prod", "app-factory"]))
	matched(msgs, "changes protected labels")
}

test_denies_dropping_the_lane_label if {
	msgs := denials(stack_update(["env:prod"], []))
	matched(msgs, "changes protected labels")
}

# Guardrail-gating labels decide which PLAN policies evaluate a stack and which stacks get
# proposed-run withholding — claiming or shedding one is the same class of privilege change.
test_denies_claiming_a_guardrail_label if {
	msgs := denials(stack_update(["env:dev"], ["env:dev", "engine"]))
	matched(msgs, "changes protected labels")
}

test_denies_dropping_a_guardrail_label if {
	msgs := denials(stack_update(["platform-factory"], []))
	matched(msgs, "changes protected labels")
}

test_allows_unrelated_label_change if {
	msgs := denials(stack_update(["env:prod", "old"], ["env:prod", "new"]))
	not matched(msgs, "changes protected labels")
}

test_allows_stack_update_with_no_labels_at_all if {
	msgs := denials(stack_update([], []))
	not matched(msgs, "changes protected labels")
}

# Terraform omits unknown values from `after`, so a missing labels key used to read as
# "every env:* label was removed" and denied a legitimate run.
test_does_not_deny_when_new_labels_are_unknown if {
	fixture := {"terraform": {"resource_changes": [{
		"address": "spacelift_stack.env",
		"type": "spacelift_stack",
		"change": {
			"actions": ["update"],
			"before": {"name": "app-prod", "labels": ["env:prod"]},
			"after": {"name": "app-prod"},
		},
	}]}}

	not matched(denials(fixture), "changes protected labels")
	matched(warnings(fixture), "unknown at plan time")
}

test_ignores_non_stack_resources if {
	msgs := denials({"terraform": {"resource_changes": [{
		"address": "spacelift_space.team",
		"type": "spacelift_space",
		"change": {
			"actions": ["update"],
			"before": {"labels": ["env:dev"]},
			"after": {"labels": ["env:prod"]},
		},
	}]}})

	not matched(msgs, "changes protected labels")
}
