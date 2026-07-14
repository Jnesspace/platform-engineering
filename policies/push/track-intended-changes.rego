# GIT_PUSH: track only pushes to the stack's branch that touch its project root; propose PRs targeting that branch; ignore everything else.
package spacelift

import rego.v1

affected if {
	some file in input.push.affected_files
	startswith(file, sprintf("%s/", [input.stack.project_root]))
}

is_pr if not is_null(input.pull_request)

track if {
	affected
	not is_pr
	input.push.branch == input.stack.branch
}

propose if {
	affected
	is_pr
	input.pull_request.base.branch == input.stack.branch
}

ignore if not affected

sample := true
