# GIT_PUSH: propose runs only for same-repo PRs from trusted authors; ignore fork and unknown-author PRs.
package spacelift

import rego.v1

trusted_authors := {"Jnesspace"}

is_pr if not is_null(input.pull_request)

trusted if {
	input.pull_request.author in trusted_authors
	input.pull_request.head_owner == input.stack.namespace
}

propose if {
	is_pr
	trusted
}

ignore if {
	is_pr
	not trusted
}

track if {
	not is_pr
	input.push.branch == input.stack.branch
}

sample := true
