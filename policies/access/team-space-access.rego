# ACCESS: teams get write on stacks labeled team:<name>, read on stacks labeled visibility:org; everything else stays hidden.
package spacelift

import rego.v1

write if {
	some team in input.session.teams
	sprintf("team:%s", [lower(team)]) in input.stack.labels
}

read if write

read if "visibility:org" in input.stack.labels

sample := true
