# PLAN: the whole model rests on elevation being created only by root-admin bootstrap. Any stack that can mint a Spacelift role grant or a long-lived AWS key can mint its own privilege, so block both. The bootstrap layer, whose whole job is minting elevation, is exempted structurally — see the boundary below — so this policy is safe to attach at "*" and stays correct the day bootstrap/ is run as a stack.
package spacelift

import rego.v1

# Spacelift control-plane grants: updating one is as good as creating it, since the
# attachment's role or space can simply be repointed.
blocked_spacelift_types := {
	"spacelift_role",
	"spacelift_role_attachment",
	"spacelift_user",
	"spacelift_api_key",
	"spacelift_idp_group_mapping",
}

# Long-lived AWS credentials: the repo vends OIDC-federated roles instead.
blocked_aws_types := {
	"aws_iam_user",
	"aws_iam_user_login_profile",
	"aws_iam_user_policy_attachment",
	"aws_iam_access_key",
}

#
# THE BOUNDARY: which runs are the bootstrap layer, stated so an engine cannot claim to be one.
#
# It is keyed on project_root — the directory whose Terraform the stack runs, i.e. the code's
# identity. Three properties make it hold where a label would not:
#
#  1. `input.spacelift.stack.project_root` is a STACK SETTING in the Spacelift control plane, not
#     repo content. Changing it needs stack write, which is the privilege this policy protects.
#  2. It is NOT `input.spacelift.run.runtime_config.project_root`. That one is forgeable:
#     .spacelift/config.yml can override it, and proposed-run-safety.rego already treats edits to
#     that file as a plan-time RCE path. The stack setting is the unforgeable half of the pair.
#  3. An engine cannot vend itself a stack rooted here either — launcher-engine-guardrail.rego
#     denies a vended project_root under these prefixes.
#
bootstrap_project_roots := {"bootstrap/"}

# Labels appear below only to REVOKE the exemption, never to grant it. A stack can influence its
# own labels, so a label that buys privilege is forgeable — but a label that removes privilege can
# only ever be forged against yourself, which is why the launcher guardrail can treat privileged
# labels as claims and this policy can still trust them in the deny direction.
bootstrap_disqualifying_labels := {"engine", "poc:nonadmin-launcher", "platform-factory", "app-factory"}

bootstrap_stack_labels := object.get(input, ["spacelift", "stack", "labels"], [])

bootstrap_disqualified if {
	some label in bootstrap_stack_labels
	label in bootstrap_disqualifying_labels
}

# An absent or non-string project_root leaves this undefined, so the deny applies. Failing closed is
# the only safe direction for an exemption.
bootstrap_layer_run if {
	root := input.spacelift.stack.project_root
	is_string(root)
	some prefix in bootstrap_project_roots
	startswith(root, prefix)
	not bootstrap_disqualified
}

deny contains msg if {
	not bootstrap_layer_run
	some r in input.terraform.resource_changes
	r.type in blocked_spacelift_types
	some action in r.change.actions
	action in {"create", "update"}

	msg := sprintf("%s %s (%s) is blocked: elevation is created by the root-admin bootstrap, not by a stack", [action, r.type, r.address])
}

# Deliberately NOT exempted for the bootstrap layer: the repo vends OIDC-federated roles
# everywhere, so nothing legitimately needs a long-lived AWS credential — including bootstrap.
deny contains msg if {
	some r in input.terraform.resource_changes
	r.type in blocked_aws_types
	"create" in r.change.actions

	msg := sprintf("creating %s (%s) is blocked: use an OIDC-federated role, not a long-lived credential", [r.type, r.address])
}

#
# IAM document inspection: blocking resource TYPES leaves the content of ordinary role/policy
# documents unchecked, so a stack whose runtime role has iam:* (anything not vended through the
# boundary-capped factory) could mint privilege with an inline wildcard grant. The helpers are
# copied from iam-factory-trust-boundary.rego on purpose: Spacelift evaluates each policy in
# isolation, so a shared library file is impossible — the consistency test keeps the two in step.
#

# The platform-factory stack's documents are already inspected by iam-factory-trust-boundary.rego
# (off-catalog actions, NotAction, wildcard grants); repeating it here would double-report, and
# the factory's own boundary policy is Allow-* by design.
document_inspection_exempt_labels := {"platform-factory"}

document_inspection_exempt if {
	some label in bootstrap_stack_labels
	label in document_inspection_exempt_labels
}

documented_policy_types := {
	"aws_iam_policy",
	"aws_iam_role_policy",
	"aws_iam_user_policy",
	"aws_iam_group_policy",
}

# Helpers are piv_-prefixed: `opa test`/`opa check` merge every policies/ file into one package,
# so an unprefixed copy would collide with trust-boundary's identical helpers.
piv_as_set(value) := {value} if is_string(value)

piv_as_set(value) := {v | some v in value} if is_array(value)

piv_statements(doc) := doc.Statement if is_array(doc.Statement)

piv_statements(doc) := [doc.Statement] if is_object(doc.Statement)

piv_policy_document(resource) := doc if {
	raw := resource.change.after.policy
	is_string(raw)
	doc := json.unmarshal(raw)
}

piv_allow_statements(resource) := [s |
	some s in piv_statements(piv_policy_document(resource))
	s.Effect == "Allow"
]

changed_policy_documents := [r |
	some r in input.terraform.resource_changes
	r.type in documented_policy_types
	some action in r.change.actions
	action in {"create", "update"}
]

# A wildcard Action in an Allow is privilege minting, whatever the resource scope.
deny contains msg if {
	not bootstrap_layer_run
	not document_inspection_exempt
	some r in changed_policy_documents
	some s in piv_allow_statements(r)
	some action in piv_as_set(s.Action)
	action == "*"

	msg := sprintf("%s grants Action \"*\": enumerate the actions a workload needs", [r.address])
}

# NotAction inverts an allow into "everything except" — the classic way past an action allowlist.
deny contains msg if {
	not bootstrap_layer_run
	not document_inspection_exempt
	some r in changed_policy_documents
	some s in piv_statements(piv_policy_document(r))
	s.NotAction

	msg := sprintf("%s uses NotAction in %s: grants must enumerate their actions", [r.address, r.type])
}

# PassRole with no resource pin hands every role the stack can reach to whatever it controls.
deny contains msg if {
	not bootstrap_layer_run
	not document_inspection_exempt
	some r in changed_policy_documents
	some s in piv_allow_statements(r)
	some action in piv_as_set(s.Action)
	action == "iam:PassRole"
	"*" in piv_as_set(s.Resource)

	msg := sprintf("%s allows iam:PassRole on \"*\": pin the specific roles that may be passed", [r.address])
}

# Policies embedding not-yet-known ARNs are absent from `after` on a first plan (same Terraform
# behaviour as the trust-boundary policy's unknown-document case). Say so rather than pass silently.
warn contains msg if {
	not bootstrap_layer_run
	not document_inspection_exempt
	some r in changed_policy_documents
	not is_string(object.get(r.change, ["after", "policy"], null))

	msg := sprintf("%s has no policy document in the plan (unknown at plan time); its grants could not be inspected", [r.address])
}

sample := true
