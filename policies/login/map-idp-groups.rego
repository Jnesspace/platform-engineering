# LOGIN: the one global policy. Account membership grants login; IdP groups grant Space Admin on the matching team:<name> Space. Login policies are merged account-wide, so keep this the only one.
package spacelift

import rego.v1

admin_team := "platform-engineering"

# `teams` is absent on API-key and other machine sessions, so it cannot gate login — gating on
# it locks out every machine session, including the engines' own API access.
teams := object.get(input, ["session", "teams"], [])

allow if input.session.member

# Machine sessions carry no IdP groups; their permissions come from role bindings, not here.
allow if input.session.machine

# No explicit `deny` rule: the login default is already deny when nothing matches, and a
# boolean `deny` would collide with the PLAN policies' set-valued `deny` under `opa test`.

# The one standing privilege in the repo; everything else is stack-bound elevation.
admin if {
	input.session.member
	admin_team in teams
}

roles[space.id] contains "space-admin" if {
	input.session.member
	some space in input.spaces
	some team in teams
	sprintf("team:%s", [lower(team)]) in space.labels
}

roles[space.id] contains "space-reader" if {
	input.session.member
	some space in input.spaces
	"shared" in space.labels
}

sample := true
