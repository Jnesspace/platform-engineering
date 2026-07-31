package tests.notification.notify_failed_runs

import data.spacelift
import rego.v1

routed(fixture) := s if {
	s := spacelift.slack with input as fixture
}

run_update(state, run_type) := {
	"account": {"name": "example"},
	"run_updated": {
		"state": state,
		"username": "alice",
		"note": "",
		"run": {
			"id": "01JEXAMPLE7KXV3MNBYPSH88AB",
			"state": state,
			"type": run_type,
			"branch": "main",
			"triggered_by": null,
			"drift_detection": false,
			"policy_receipts": [],
		},
		"stack": {
			"id": "jimmy-app-01JEXAMPLE7KXV3MNBYPSH88AX",
			"name": "jimmy-app",
			"labels": ["env:d"],
			"branch": "main",
			"repository": "platform-engineering",
			"space": {"id": "jimmy-team", "name": "jimmy-team", "labels": []},
		},
		"timing": [],
		"urls": {"run": "https://example.app.spacelift.io/stack/jimmy-app/run/01JEX"},
	},
	"webhook_endpoints": [],
}

test_routes_a_failed_tracked_run if {
	messages := routed(run_update("FAILED", "TRACKED"))

	count(messages) == 1
	some m in messages
	m.channel_id == spacelift.slack_channel_id
	contains(m.message, "01JEXAMPLE7KXV3MNBYPSH88AB")
	contains(m.message, "https://example.app.spacelift.io/stack/jimmy-app/run/01JEX")
}

test_stays_quiet_on_a_successful_run if {
	count(routed(run_update("FINISHED", "TRACKED"))) == 0
}

# Proposed runs already report back to the pull request.
test_stays_quiet_on_a_failed_proposed_run if {
	count(routed(run_update("FAILED", "PROPOSED"))) == 0
}

# Notification policies also fire for module versions and internal errors, where run_updated is
# absent entirely.
test_stays_quiet_on_an_internal_error_event if {
	fixture := {
		"account": {"name": "example"},
		"internal_error": {"error": "boom", "message": "worker lost", "severity": "ERROR"},
	}

	count(routed(fixture)) == 0
}

test_stays_quiet_on_a_null_run_updated if {
	count(routed({"account": {"name": "example"}, "run_updated": null})) == 0
}
