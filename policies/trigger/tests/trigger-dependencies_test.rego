package tests.trigger.trigger_dependencies

import data.spacelift
import rego.v1

triggered(fixture) := t if {
	t := spacelift.trigger with input as fixture
}

upstream := "platform-network-01JEXAMPLE7KXV3MNBYPSH88AX"

stack(id, labels) := {
	"id": id,
	"name": id,
	"labels": labels,
	"branch": "main",
	"repository": "platform-engineering",
	"state": "FINISHED",
	"autodeploy": false,
	"worker_pool": {"public": false},
}

finished(state, run_type, stacks) := {
	"run": {
		"id": "01JEXAMPLE7KXV3MNBYPSH88AB",
		"state": state,
		"type": run_type,
		"branch": "main",
		"triggered_by": null,
		"drift_detection": false,
		"flags": [],
		"creator_session": {"login": "alice", "machine": false, "admin": false, "teams": []},
	},
	"stack": stack(upstream, ["platform-network"]),
	"stacks": stacks,
	"workflow": [],
}

test_triggers_dependents_after_a_successful_tracked_run if {
	stacks := [
		stack(upstream, ["platform-network"]),
		stack("app-a", [sprintf("depends-on:%s", [upstream])]),
		stack("app-b", [sprintf("depends-on:%s", [upstream])]),
		stack("app-c", ["depends-on:something-else"]),
	]

	triggered(finished("FINISHED", "TRACKED", stacks)) == {"app-a", "app-b"}
}

test_does_not_trigger_after_a_failed_run if {
	stacks := [stack("app-a", [sprintf("depends-on:%s", [upstream])])]

	count(triggered(finished("FAILED", "TRACKED", stacks))) == 0
}

test_does_not_trigger_after_a_proposed_run if {
	stacks := [stack("app-a", [sprintf("depends-on:%s", [upstream])])]

	count(triggered(finished("FINISHED", "PROPOSED", stacks))) == 0
}

# input.stacks includes the stack that just finished; a self-referential label would otherwise
# retrigger it forever, because policy-triggered runs re-evaluate this policy.
test_never_triggers_itself if {
	stacks := [stack(upstream, ["platform-network", sprintf("depends-on:%s", [upstream])])]

	count(triggered(finished("FINISHED", "TRACKED", stacks))) == 0
}

test_no_dependents_means_no_triggers if {
	stacks := [stack("app-a", ["env:d"])]

	count(triggered(finished("FINISHED", "TRACKED", stacks))) == 0
}
