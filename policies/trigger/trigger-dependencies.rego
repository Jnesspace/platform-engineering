# TRIGGER: after a successful tracked run, trigger every stack labeled depends-on:<this stack's id>, so dependency order lives on the dependent stack instead of in a central list.
package spacelift

import rego.v1

trigger contains stack.id if {
	input.run.state == "FINISHED"
	input.run.type == "TRACKED"

	some stack in input.stacks

	# input.stacks includes the stack that just finished; a self-referential label would
	# otherwise retrigger it forever, since policy-triggered runs re-evaluate this policy.
	stack.id != input.stack.id

	sprintf("depends-on:%s", [input.stack.id]) in stack.labels
}

sample := true
