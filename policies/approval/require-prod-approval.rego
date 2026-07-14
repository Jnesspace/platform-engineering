# APPROVAL: stacks labeled env:prod need two approvals and no rejections; everything else auto-approves.
package spacelift

import rego.v1

is_prod if "env:prod" in input.stack.labels

approve if not is_prod

approve if {
	is_prod
	count(input.reviews.current.approvals) >= 2
	count(input.reviews.current.rejections) == 0
}

reject if count(input.reviews.current.rejections) > 0

sample := true
