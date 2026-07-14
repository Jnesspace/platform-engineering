# NOTIFICATION: send non-proposed run failures to the platform Slack channel with a link to the run.
package spacelift

import rego.v1

slack contains {
	"channel_id": "C0PLATFORMOPS",
	"message": sprintf("Run %s failed on stack %s: %s", [input.run_updated.run.id, input.run_updated.stack.id, input.run_updated.urls.run]),
} if {
	input.run_updated.run.state == "FAILED"
	input.run_updated.run.type != "PROPOSED"
}

sample := true
