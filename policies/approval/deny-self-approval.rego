# APPROVAL: require at least one approval from someone other than the run's triggerer; any rejection blocks.
package spacelift

import rego.v1

approve if {
	some approval in input.reviews.current.approvals
	approval.author != input.run.triggered_by
}

reject if count(input.reviews.current.rejections) > 0

sample := true
