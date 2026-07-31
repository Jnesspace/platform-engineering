# PLAN (hardening-backlog #6, second half): reads the actual IAM JSON the iam-factory is about to apply. The catalog gate and the permissions boundary are both written by the engine, so an edited engine can drop them; the trust policy and the inline grant, however, still have to appear in the plan. This is where an off-catalog grant, an unpinned OIDC `sub`/`aud`, a foreign OIDC provider, a detached boundary, or a weakened boundary gets caught.
package spacelift

import rego.v1

trust_stack_labels := {"platform-factory"}

# Suffix, not full ARN, so the policy needs no AWS account ID baked in.
boundary_arn_suffix := ":policy/spacelift-space-boundary"

boundary_policy_name := "spacelift-space-boundary"

# The only OIDC provider a vended role may trust: the Spacelift account endpoint. Matched by
# host suffix — the account subdomain is a var the policy cannot see, but any IdP that is not
# *.app.spacelift.io (a foreign provider in the same AWS account) is not the factory's issuer.
oidc_provider_arn_infix := ":oidc-provider/"

oidc_provider_host_suffix := ".app.spacelift.io"

# Exactly the sub shapes patterns/iam-factory/main.tf pins: space:<space-id>:<stack>:scope:<rw>.
# A `*` in the space position fails this on purpose.
trust_sub_pattern := `^space:[A-Za-z0-9_-]+:[^:]*:scope:(read|write)$`

# What the boundary's Deny statement must keep covering.
boundary_required_denies := {"iam:*", "organizations:*", "account:*"}

# sts:GetCallerIdentity is the factory's documented provider baseline; everything else under
# sts: is credential-vending and must not be grantable.
trust_allowed_sts := {"sts:GetCallerIdentity"}

trust_escalation_prefixes := {"iam:", "organizations:", "account:"}

trust_run if {
	some label in input.spacelift.stack.labels
	label in trust_stack_labels
}

as_set(value) := {value} if is_string(value)

as_set(value) := {v | some v in value} if is_array(value)

# Statement may be a lone object or a list; normalise before iterating.
statements(doc) := doc.Statement if is_array(doc.Statement)

statements(doc) := [doc.Statement] if is_object(doc.Statement)

document(resource, attribute) := doc if {
	raw := resource.change.after[attribute]
	is_string(raw)
	doc := json.unmarshal(raw)
}

allow_statements(resource, attribute) := [s |
	some s in statements(document(resource, attribute))
	s.Effect == "Allow"
]

# Any condition operator other than these leaves the set empty, which the "no `:sub` condition"
# deny below treats as unpinned — the safe direction.
sub_conditions(statement) := {value |
	some operator, conditions in statement.Condition
	operator in {"StringLike", "StringEquals"}
	some key, raw in conditions
	endswith(key, ":sub")
	some value in as_set(raw)
}

aud_conditions(statement) := {value |
	some operator, conditions in statement.Condition
	operator in {"StringLike", "StringEquals"}
	some key, raw in conditions
	endswith(key, ":aud")
	some value in as_set(raw)
}

escalating_action(action) if action == "*"

escalating_action(action) if {
	some prefix in trust_escalation_prefixes
	startswith(action, prefix)
}

escalating_action(action) if {
	startswith(action, "sts:")
	not action in trust_allowed_sts
}

changed_roles := [r |
	some r in input.terraform.resource_changes
	r.type == "aws_iam_role"
	some action in r.change.actions
	action in {"create", "update"}
]

changed_role_policies := [r |
	some r in input.terraform.resource_changes
	r.type == "aws_iam_role_policy"
	some action in r.change.actions
	action in {"create", "update"}
]

#
# Permissions boundary: the runtime hard cap on every vended role.
#

deny contains msg if {
	trust_run
	some r in changed_roles
	boundary := r.change.after.permissions_boundary
	is_string(boundary)
	not endswith(boundary, boundary_arn_suffix)
	msg := sprintf("%s attaches boundary %q instead of one ending in %q", [r.address, boundary, boundary_arn_suffix])
}

# Terraform omits unknown values from `after`, so on the very first factory apply the boundary ARN
# is genuinely not yet knowable. Warn rather than fail a legitimate bootstrap; on every later run
# the ARN is in state and the deny above applies.
#
# object.get, not `not is_string(r.change.after.x)`: OPA hoists a nested reference out of `not`, so
# the negation is undefined rather than true when the key is absent — the only case this checks.
warn contains msg if {
	trust_run
	some r in changed_roles
	not is_string(object.get(r.change, ["before", "permissions_boundary"], null))
	not is_string(object.get(r.change, ["after", "permissions_boundary"], null))
	msg := sprintf("%s has no permissions_boundary in the plan (unknown at plan time); confirm it is the factory boundary", [r.address])
}

# ...but an absent `after` is only ambiguous when `before` was absent too. If the role HAD a
# boundary and the plan drops it, that is a detach, not an unknown — and detaching the runtime
# cap must fail, not advise.
deny contains msg if {
	trust_run
	some r in changed_roles
	before := object.get(r.change, ["before", "permissions_boundary"], null)
	is_string(before)
	not is_string(object.get(r.change, ["after", "permissions_boundary"], null))
	msg := sprintf("%s removes permissions_boundary %q; the runtime cap may be re-pinned, never detached", [r.address, before])
}

# A Deny statement only counts as coverage if it can actually fire: unconditional, Resource "*",
# and no NotResource indirection. A deny behind an impossible condition, or scoped to an
# irrelevant resource, names the right actions and stops nothing.
effective_deny(statement) if {
	statement.Effect == "Deny"
	not statement.Condition
	not statement.NotResource
	"*" in as_set(statement.Resource)
}

# The boundary document itself, in case the tampering is to weaken the cap rather than detach it.
deny contains msg if {
	trust_run
	some r in input.terraform.resource_changes
	r.type == "aws_iam_policy"
	r.change.after.name == boundary_policy_name
	doc := document(r, "policy")
	denied := {action |
		some s in statements(doc)
		effective_deny(s)
		some action in as_set(s.Action)
	}
	missing := boundary_required_denies - denied
	count(missing) > 0
	msg := sprintf("%s weakens the permissions boundary: it no longer unconditionally denies %v", [r.address, sort(missing)])
}

#
# OIDC trust policy: what may assume a vended role.
#

deny contains msg if {
	trust_run
	some r in changed_roles
	some s in allow_statements(r, "assume_role_policy")
	some action in as_set(s.Action)
	action != "sts:AssumeRoleWithWebIdentity"
	msg := sprintf("%s trusts %q; a vended role may only be assumed via sts:AssumeRoleWithWebIdentity", [r.address, action])
}

# No Federated principal means the trust is not OIDC at all — an AWS principal or "*".
deny contains msg if {
	trust_run
	some r in changed_roles
	some s in allow_statements(r, "assume_role_policy")
	not object.get(s, ["Principal", "Federated"], false)
	msg := sprintf("%s has a trust statement with no Federated principal; it is not OIDC-scoped", [r.address])
}

spacelift_oidc_provider(provider) if {
	contains(provider, oidc_provider_arn_infix)
	endswith(provider, oidc_provider_host_suffix)
}

# A Federated principal is not enough: any OIDC provider in the account (or one an edited
# engine just created) could mint tokens with a Space-shaped sub. The provider must be the
# Spacelift account endpoint itself. (Absent Federated is the previous rule's case, so this
# one only fires on a non-empty string.)
deny contains msg if {
	trust_run
	some r in changed_roles
	some s in allow_statements(r, "assume_role_policy")
	provider := object.get(s, ["Principal", "Federated"], "")
	provider != ""
	not spacelift_oidc_provider(provider)
	msg := sprintf("%s trusts OIDC provider %q, which is not the Spacelift account endpoint (*%s)", [r.address, provider, oidc_provider_host_suffix])
}

# The aud claim pins the token to this Spacelift account; without it a token from ANY
# Spacelift account sharing the OIDC host shape would be accepted.
deny contains msg if {
	trust_run
	some r in changed_roles
	some s in allow_statements(r, "assume_role_policy")
	count(aud_conditions(s)) == 0
	msg := sprintf("%s has no `:aud` condition; its trust policy is not pinned to this Spacelift account", [r.address])
}

deny contains msg if {
	trust_run
	some r in changed_roles
	some s in allow_statements(r, "assume_role_policy")
	some aud in aud_conditions(s)
	not endswith(aud, oidc_provider_host_suffix)
	msg := sprintf("%s trusts aud %q, which is not the Spacelift account endpoint (*%s)", [r.address, aud, oidc_provider_host_suffix])
}

# The sub condition is the entire Space pin. Without it, every stack in the account can assume
# the role, which is precisely the boundary the factory exists to draw.
deny contains msg if {
	trust_run
	some r in changed_roles
	some s in allow_statements(r, "assume_role_policy")
	count(sub_conditions(s)) == 0
	msg := sprintf("%s has no `:sub` condition; its trust policy is not pinned to a Space", [r.address])
}

deny contains msg if {
	trust_run
	some r in changed_roles
	some s in allow_statements(r, "assume_role_policy")
	some sub in sub_conditions(s)
	not regex.match(trust_sub_pattern, sub)
	msg := sprintf("%s trusts sub %q, which is not pinned to a single Space (expected %s)", [r.address, sub, trust_sub_pattern])
}

# Adding a service to a *new* Space leaves the trust document unknown at plan time (it embeds the
# Space ID), so there is nothing to inspect. Say so rather than pass silently.
warn contains msg if {
	trust_run
	some r in changed_roles
	not is_string(object.get(r.change, ["after", "assume_role_policy"], null))
	msg := sprintf("%s has no assume_role_policy in the plan (unknown at plan time, or removed); its Space pin could not be verified", [r.address])
}

#
# Inline grant: the catalog's union of actions. The policy cannot read catalog.yaml, but it can
# refuse the actions no catalog entry may ever contain.
#

deny contains msg if {
	trust_run
	some r in changed_role_policies
	some s in allow_statements(r, "policy")
	some action in as_set(s.Action)
	escalating_action(action)
	msg := sprintf("%s grants %q, which is off-catalog and outside the permissions boundary", [r.address, action])
}

# NotAction inverts an allow into "everything except", the classic way to smuggle a wildcard
# past an action allowlist.
deny contains msg if {
	trust_run
	some r in changed_role_policies
	some s in statements(document(r, "policy"))
	s.NotAction
	msg := sprintf("%s uses NotAction; vended grants must enumerate their actions", [r.address])
}

sample := true
