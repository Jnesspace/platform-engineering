# PLAN: deny creation of Spacelift role grants and long-lived IAM users.
package spacelift

import rego.v1

blocked_types := {
	"spacelift_role",
	"spacelift_role_attachment",
	"aws_iam_user",
	"aws_iam_user_login_profile",
	"aws_iam_access_key",
}

deny contains msg if {
	some r in input.terraform.resource_changes
	r.type in blocked_types
	"create" in r.change.actions
	msg := sprintf("creating %s (%s) is blocked; request it through the platform team", [r.type, r.address])
}

sample := true
