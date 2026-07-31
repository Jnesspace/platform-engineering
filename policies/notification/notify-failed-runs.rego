# NOTIFICATION: route real (non-proposed) run failures to the platform Slack channel with a link. Proposed runs already report back to the pull request.
package spacelift

import rego.v1

# Account-specific, so it is a placeholder here: bootstrap/governance substitutes var.slack_channel_id
# at publish time, and refuses to publish this policy at all while that variable is unset. A wrong
# channel ID fails silently — Slack simply drops the message — which is why it must not be possible
# to ship one by forgetting. Left as a plain string literal so `opa test policies/` runs this file
# standalone.
slack_channel_id := "REPLACE_WITH_SLACK_CHANNEL_ID"

# Notification policies also fire for module versions and internal errors, where run_updated is
# absent; the documented idiom is to guard rather than rely on undefined lookups.
run_failed if {
	input.run_updated != null
	input.run_updated.run.state == "FAILED"
	input.run_updated.run.type != "PROPOSED"
}

slack contains {
	"channel_id": slack_channel_id,
	"message": sprintf(
		"Run %s failed on stack %s: %s",
		[input.run_updated.run.id, input.run_updated.stack.id, input.run_updated.urls.run],
	),
} if {
	run_failed
}

sample := true
