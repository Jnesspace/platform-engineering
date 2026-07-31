package tests.login.map_idp_groups

import data.spacelift
import rego.v1

allowed(fixture) if {
	spacelift.allow with input as fixture
}

is_admin(fixture) if {
	spacelift.admin with input as fixture
}

granted(fixture) := r if {
	r := spacelift.roles with input as fixture
}

spaces := [
	{"id": "payments-01JEXAMPLE7KXV3MNBYPSH88AX", "name": "payments", "labels": ["team:payments"]},
	{"id": "analytics-01JEXAMPLE7KXV3MNBYPSH88AY", "name": "analytics", "labels": ["team:analytics"]},
	{"id": "shared-01JEXAMPLE7KXV3MNBYPSH88AZ", "name": "shared", "labels": ["shared"]},
]

session(overrides) := json.patch(
	{
		"request": {"remote_ip": "10.0.0.1", "timestamp_ns": 1700000000000000000},
		"session": {
			"login": "alice",
			"name": "Alice",
			"member": true,
			"machine": false,
			"admin": false,
			"teams": ["Payments"],
			"idp_subject": "user:alice",
			"creator_ip": "10.0.0.1",
		},
		"spaces": spaces,
		"roles": [{"id": "space-admin", "slug": "space-admin", "name": "Space Admin", "ulid": "01H"}],
	},
	overrides,
)

#
# Login. Gating on team membership locked out members with no IdP groups and, worse, every
# machine session — including the engines' own API access.
#

test_member_may_log_in if {
	allowed(session([]))
}

test_member_with_no_teams_may_still_log_in if {
	allowed(session([{"op": "replace", "path": "/session/teams", "value": []}]))
}

test_machine_session_with_no_teams_may_log_in if {
	fixture := json.remove(
		session([
			{"op": "replace", "path": "/session/machine", "value": true},
			{"op": "replace", "path": "/session/member", "value": false},
		]),
		["/session/teams"],
	)

	allowed(fixture)
}

test_non_member_human_is_not_allowed if {
	fixture := session([
		{"op": "replace", "path": "/session/member", "value": false},
		{"op": "replace", "path": "/session/machine", "value": false},
	])

	not allowed(fixture)
}

#
# Admin
#

test_platform_team_is_admin if {
	fixture := session([{
		"op": "replace",
		"path": "/session/teams",
		"value": ["platform-engineering"],
	}])

	is_admin(fixture)
}

test_app_team_is_not_admin if {
	not is_admin(session([]))
}

test_non_member_claiming_the_platform_team_is_not_admin if {
	fixture := session([
		{"op": "replace", "path": "/session/teams", "value": ["platform-engineering"]},
		{"op": "replace", "path": "/session/member", "value": false},
	])

	not is_admin(fixture)
}

#
# Space role assignment
#

test_team_gets_space_admin_on_its_own_space_only if {
	roles := granted(session([]))

	roles["payments-01JEXAMPLE7KXV3MNBYPSH88AX"] == {"space-admin"}
	not "analytics-01JEXAMPLE7KXV3MNBYPSH88AY" in object.keys(roles)
}

test_shared_space_is_read_only if {
	roles := granted(session([]))

	roles["shared-01JEXAMPLE7KXV3MNBYPSH88AZ"] == {"space-reader"}
}

test_team_label_match_is_case_insensitive if {
	roles := granted(session([{
		"op": "replace",
		"path": "/session/teams",
		"value": ["ANALYTICS"],
	}]))

	roles["analytics-01JEXAMPLE7KXV3MNBYPSH88AY"] == {"space-admin"}
}

test_non_member_gets_no_space_roles if {
	roles := granted(session([{"op": "replace", "path": "/session/member", "value": false}]))

	count(roles) == 0
}
