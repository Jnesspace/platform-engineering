# Tests live in tests/ so the governance stack's fileset("policies", "*/*.rego") does not publish
# them as policies. `opa test policies/` still finds them.
package tests.plan.cap_new_resources

import data.spacelift
import rego.v1

# Every .rego in policies/ shares `package spacelift`, so `opa test` merges them all while
# Spacelift evaluates each in isolation. Assert on this policy's own message, never on count(deny).
denials(fixture) := msgs if {
	msgs := spacelift.deny with input as fixture
}

matched(msgs, substring) if {
	some m in msgs
	contains(m, substring)
}

creates_of(type, n) := [r |
	some i in numbers.range(1, n)
	r := {
		"address": sprintf("%s.r[%d]", [type, i]),
		"type": type,
		"name": sprintf("r%d", [i]),
		"change": {"actions": ["create"], "after": {"name": sprintf("r-%d", [i])}},
	}
]

plan(changes) := {"terraform": {"resource_changes": changes, "terraform_version": "1.5.7"}}

fixture(n) := plan(creates_of("aws_s3_bucket", n))

#
# Infrastructure: things that cost money or hold data.
#

test_denies_plan_over_the_cap if {
	matched(denials(fixture(26)), "plan creates 26 infrastructure resources; cap is 25")
}

test_allows_plan_at_the_cap if {
	not matched(denials(fixture(25)), "cap is 25")
}

test_allows_small_plan if {
	not matched(denials(fixture(3)), "cap is 25")
}

# A replacement is a delete+create pair and still counts, since replacing 26 resources is as
# disruptive as creating them.
test_counts_the_create_half_of_a_replacement if {
	replacements := [r |
		some i in numbers.range(1, 26)
		r := {
			"address": sprintf("aws_s3_bucket.b[%d]", [i]),
			"type": "aws_s3_bucket",
			"change": {"actions": ["delete", "create"], "after": {}},
		}
	]

	matched(denials(plan(replacements)), "cap is 25")
}

#
# Control plane: the second bucket, and the reason it exists.
#

# The case that made the single cap a guaranteed false positive: bootstrap/governance publishing
# this library into two Spaces creates ~29 spacelift_policy plus its two terraform_data gates.
test_allows_the_governance_first_apply if {
	changes := array.concat(
		creates_of("spacelift_policy", 29),
		creates_of("terraform_data", 2),
	)

	not matched(denials(plan(changes)), "cap is 25")
	not matched(denials(plan(changes)), "cap is 75")
}

# iam-factory at max_vended_services = 10: Spaces, contexts, environment variables and gates.
test_allows_a_full_iam_factory_apply if {
	changes := array.concat(
		array.concat(creates_of("spacelift_space", 10), creates_of("spacelift_context", 10)),
		array.concat(creates_of("spacelift_environment_variable", 20), creates_of("terraform_data", 12)),
	)

	not matched(denials(plan(changes)), "cap is 25")
	not matched(denials(plan(changes)), "cap is 75")
}

test_denies_control_plane_over_its_own_cap if {
	matched(
		denials(plan(creates_of("spacelift_policy", 76))),
		"plan creates 76 Spacelift control-plane objects; cap is 75",
	)
}

test_allows_control_plane_at_its_cap if {
	not matched(denials(plan(creates_of("spacelift_policy", 75))), "cap is 75")
}

# The buckets are counted separately: control-plane volume must not buy infrastructure headroom.
test_control_plane_volume_does_not_raise_the_infrastructure_cap if {
	changes := array.concat(
		creates_of("spacelift_policy", 40),
		creates_of("aws_s3_bucket", 26),
	)

	matched(denials(plan(changes)), "plan creates 26 infrastructure resources; cap is 25")
}

# Privilege objects were deliberately left OUT of the control-plane set, so they stay under 25
# alongside real infrastructure. If someone moves them, this fails.
test_privilege_objects_stay_under_the_strict_cap if {
	matched(
		denials(plan(creates_of("spacelift_role_attachment", 26))),
		"plan creates 26 infrastructure resources; cap is 25",
	)
}

#
# Destroy direction: a request YAML LOSING entries destroys what the engine vended — the same
# blast radius with no create count at all.
#

deletes_of(type, n) := [r |
	some i in numbers.range(1, n)
	r := {
		"address": sprintf("%s.r[%d]", [type, i]),
		"type": type,
		"name": sprintf("r%d", [i]),
		"change": {"actions": ["delete"], "before": {"name": sprintf("r-%d", [i])}},
	}
]

test_denies_a_mass_destroy if {
	matched(denials(plan(deletes_of("aws_s3_bucket", 26))), "plan destroys 26 infrastructure resources; cap is 25")
}

test_allows_destroys_at_the_cap if {
	not matched(denials(plan(deletes_of("aws_s3_bucket", 25))), "cap is 25")
}

test_denies_a_mass_control_plane_destroy if {
	matched(denials(plan(deletes_of("spacelift_stack", 76))), "plan destroys 76 Spacelift control-plane objects; cap is 75")
}

# A replacement is a delete+create pair; it already counted on the create side, and it counts
# here too — replacing 26 resources is disruptive in both directions.
test_a_replacement_counts_on_both_sides if {
	replacements := [r |
		some i in numbers.range(1, 26)
		r := {
			"address": sprintf("aws_s3_bucket.b[%d]", [i]),
			"type": "aws_s3_bucket",
			"change": {"actions": ["delete", "create"], "after": {}},
		}
	]

	msgs := denials(plan(replacements))
	matched(msgs, "plan creates 26 infrastructure resources; cap is 25")
	matched(msgs, "plan destroys 26 infrastructure resources; cap is 25")
}
