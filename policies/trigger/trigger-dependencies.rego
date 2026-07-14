# TRIGGER: after a successful tracked run, trigger every stack labeled depends-on:<this stack's id>.
package spacelift

import rego.v1

trigger contains stack.id if {
	input.run.state == "FINISHED"
	input.run.type == "TRACKED"
	some stack in input.stacks
	sprintf("depends-on:%s", [input.stack.id]) in stack.labels
}

sample := true
