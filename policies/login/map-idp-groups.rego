# LOGIN: platform team logs in as account admin; app teams get Space Admin on their team:<name> spaces; shared spaces are read-only.
package spacelift

import rego.v1

teams := input.session.teams

allow if count(teams) > 0

admin if "platform-engineering" in teams

roles[space.id] contains "space-admin" if {
	some space in input.spaces
	some team in teams
	sprintf("team:%s", [lower(team)]) in space.labels
}

roles[space.id] contains "space-reader" if {
	some space in input.spaces
	"shared" in space.labels
}

sample := true
