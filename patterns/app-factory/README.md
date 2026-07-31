# app-factory — the shopping-list engine (rung 4: converged onboarding)

A developer writes **one `platform.yaml`** in their app repo; this engine turns
it into cloud resources by composing the same dual-purpose wrappers under
[`modules/`](../../modules) that Blueprints and standalone roots use. The
developer never touches Terraform, providers, or IAM.

```
platform.yaml  ──►  app-factory (AWS)  ──►  modules/aws/<primitive> (one call per entry)
                        │
                        └──►  ONE app IAM role + policies (AWS), built from each
                              module's iam_policy_json — access to exactly what
                              was ordered, nothing else
```

## Shopping-list schema (`platform.yaml`)

```yaml
name: jimmy-app          # app name; prefixes every resource name
cloud: aws               # this engine serves aws (azure/gcp: see below)
resources:               # every key optional; entries are lists
  object_storage:
    - name: uploads
      kms_key_arn: arn:aws:kms:us-east-1:111122223333:key/1234abcd-...
  secrets:
    - name: app-secrets
      kms_key_arn: arn:aws:kms:...
      rotation_days: 30  # 0 (default) = no rotation
  database:
    - name: app
      engine: postgres   # checked, not decorative: the module is postgres-only
      kms_key_arn: arn:aws:kms:...
      multi_az: true     # synchronous standby; default false
  compute:
    - name: worker
      kms_key_arn: arn:aws:kms:...
```

`name` is the only required key per entry. **Every other key is optional and
every one of them either strengthens the posture or is security-neutral** —
that is the invariant, not a coincidence (see below). Top-level keys are exactly
`name`, `cloud`, `owner`, `resources`.

The engine reads it via `var.shopping_list_file` (default:
`../../examples/jimmy-app/platform.yaml`), or inline from
`var.shopping_list_yaml` (the Blueprint/form path, which wins).

## Who may set what: team vs. operator

The shopping list lives in the **team's own repo**. The stack variables live on
the **Spacelift stack**, which the team cannot write to. So the split is not
cosmetic — it decides who can weaken a default, and one side of it has an audit
trail:

| control | who | why |
|---|---|---|
| which resources, and their names | team | it's their app |
| `kms_key_arn` per resource | team, **from the operator's list** | a team may choose among the CMKs the platform published (`var.allowed_kms_key_arns`); it may not bring an arbitrary key, which would put the app's data under something the platform cannot read and the team can revoke |
| `rotation_days`, `multi_az` | team | strengthening only; the defaults (0, false) are the weaker end |
| `owner:` (top level) | team, operator overrides | accountability, not a privilege. `var.owner` wins because a Blueprint form and a per-env stack know the team authoritatively |
| `var.environment` | operator | the Environment tag follows the stack's `env:` lane, and `policies/plan/protect-env-labels.rego` treats `env:*` as a **privilege claim** — a team tagging itself `prod` would be making that claim |
| `var.default_kms_key_arn` | operator | CMK for every resource that doesn't name one — turns on CMK encryption env-wide without touching a team's YAML |
| `var.access_log_bucket` | operator | an audit trail's destination. A team must be able to neither switch it off nor point it at a bucket the platform doesn't own |
| `var.demo_teardown` | operator | **the** posture-weakening escape hatch (below) |
| `force_destroy`, `deletion_protection`, `skip_final_snapshot`, recovery windows, `initial_value`, network exposure | **nobody, from YAML** | the plan fails, naming the stack variable that owns the control instead |

The last row is the point. A team that could write `skip_final_snapshot: true`
in a file in its own repo would have a one-line route to making its own data
trivially destroyable — precisely the class of thing this repo's guardrails
exist to prevent. `terraform_data.shopping_list_guard` rejects those keys by
name, so the failure is "that control is the operator's, set `var.demo_teardown`
on the stack", not a silent no-op.

### Required tags

`policies/plan/enforce-required-tags.rego` denies any plan that creates a
taggable resource without **`Environment`, `Owner`, `Project`**. The engine puts
all three on `local.tags`, which reaches every `modules/aws/*` call and
`aws_iam_role.app`:

| tag | from |
|---|---|
| `Project` | the app name (`var.app_name`, else the list's `name:`) |
| `Owner` | `var.owner`, else the list's top-level `owner:` |
| `Environment` | `var.environment` only |

`app` and `managed_by` are kept alongside them — they predate the policy and are
what run logs and dashboards key on.

Both `Environment` and `Owner` are checked in
`terraform_data.shopping_list_guard`, so a stack that has not been wired fails
with *"Set TF_VAR_environment on the stack to its lane"* rather than with a
policy denial naming a bucket address. A missing input should be reported as a
missing input.

**A stack must set `TF_VAR_environment`.** `bootstrap/environments` labels each
`app-factory-<env>` stack `env:<environment>` already; the tag is the same value
through a second channel.

### Demo vs. production teardown

`modules/aws/database` now defaults to production shape: `deletion_protection =
true`, `skip_final_snapshot = false`, and a 30-day secret recovery window. Those
defaults make `terraform destroy` on a demo environment **fail outright**, and a
30-day window also keeps the secret name reserved so the next demo run cannot
re-create it.

`var.demo_teardown = true` is the one switch that gives all of that up together:
buckets get `force_destroy`, the database drops deletion protection and its
final snapshot, and credential secrets get a 0-day recovery window. It is one
flag rather than four so it cannot be half-set into an inconsistent state, and
it fires a plan-time **warning on every run** (`check
"demo_teardown_weakens_posture"`) — a production stack carrying it is a finding,
and silence is how that survives.

Set it on ephemeral/demo stacks only, e.g. `app-factory-dev`:

```sh
TF_VAR_demo_teardown=true
```

### The list is untrusted input

It comes from a team, so `terraform_data.shopping_list_guard` fails the **plan**
— before anything is created — on any of:

- the YAML not decoding to a mapping, or `resources:` not being a mapping;
- an unknown **top-level** key, or an unknown key under `resources:` (a typo
  like `object-storage` used to be silently ignored, so the team believed they
  had ordered a bucket);
- an unknown **per-entry option** — `kms_key_arm:` must fail loudly, not leave a
  team believing their bucket is CMK-encrypted when it is not;
- a key that is the operator's to set (`force_destroy`, `deletion_protection`,
  `skip_final_snapshot`, `secret_recovery_window_days`,
  `recovery_window_in_days`, `disable_api_termination`, `access_log_bucket`,
  `assign_public_ip`, `ingress_rules`, `egress_cidr_blocks`, `db_parameters`,
  `enforce_tls_resource_policy`, `iam_database_authentication_enabled`) or is
  never safe in git (`initial_value`);
- a kind that isn't a list of objects each carrying a string `name:`;
- more than `var.max_resources` entries (default 10) — an unbounded list is a
  cost and blast-radius problem;
- duplicate names within a kind;
- names outside `^[a-z0-9]([a-z0-9]|-[a-z0-9])*$` (the intersection of the S3
  bucket, RDS identifier and Secrets Manager rules) or in
  `var.reserved_names`;
- an `<app_name>-<name>` composition longer than the target service allows, or
  one S3 rejects (3-char floor, reserved `xn--` / `sthree-` / `amzn-s3-demo-`
  prefixes, reserved `-s3alias` / `--ol-s3` / `--x-s3` / `--table-s3` suffixes);
- a `secrets` name that would collide with the `<name>-db-credentials` secret
  `modules/aws/database` mints;
- an app name (from `var.app_name` **or** the list's own `name:`) that isn't
  lowercase, letter-initial and <= 40 chars;
- a `kms_key_arn` that isn't a KMS **key** ARN
  (`arn:aws:kms:<region>:<account>:key/<uuid|mrk-…>`) — alias ARNs are rejected
  because the app role's grant names that exact string and an alias grants
  nothing on the key behind it — or that isn't in `var.allowed_kms_key_arns`.
  An empty `kms_key_arn: ""` is an error too, not a silent fall-back to
  `var.default_kms_key_arn`;
- `rotation_days` outside 0-365 or non-integer; `multi_az` that isn't a boolean;
  `engine` that isn't `postgres`;
- a `var.access_log_bucket` that is one of the buckets this stack vends (a
  bucket logging to itself grows without bound);
- an `Environment` or `Owner` that would end up empty or malformed.

## Cloud coverage

This engine is the **AWS path** — the cloud wired live. It composes the
`modules/aws/*` wrappers. Azure and GCP expose the **same module interface**
(`modules/{azure,gcp}/*`, validated), so an Azure or GCP engine is this exact
file with its provider block and `modules/<cloud>/*` swapped in.

Why one root per cloud, not one root for all three? Terraform eagerly configures
**every** declared provider, so a single root declaring aws + azurerm + google
would demand all three clouds' credentials on every run — even an AWS-only one.
Per-cloud engines keep each run to one credential set. The shopping list's
`cloud:` must be `aws` here; anything else fails fast with a pointer to that
cloud's modules.

## The IAM wiring (AWS)

Every AWS module outputs `iam_policy_json` — a least-privilege policy scoped to
the one resource it created. The engine keys those by resource and attaches each
as an inline `aws_iam_role_policy` on **one** `aws_iam_role` per app. Compute
contributes nothing (apps run *on* the VM, not against the EC2 API), which is
why `modules/aws/compute` returns an empty `iam_policy_json`. Azure/GCP modules
instead expose the needed role/scope inside their `access` output; binding those
is a later rung. `var.app_role_permissions_boundary_arn` optionally caps the
role at runtime as well.

### CMKs reach the role automatically — but a boundary can still block them

When a resource carries a `kms_key_arn`, its module adds `kms:Decrypt` /
`kms:GenerateDataKey` / `kms:DescribeKey` on that key to its own
`iam_policy_json`, and the merge above carries them onto the app role. Nothing
extra to wire.

A **permissions boundary is an intersection**, though. If
`var.app_role_permissions_boundary_arn` is set and its policy does not also
allow those three actions, a CMK-encrypted bucket or secret fails at runtime
with an `AccessDenied` **naming the key** — which sends whoever debugs it to the
key policy rather than to the boundary that is actually refusing.

Terraform cannot read the boundary's document without calling IAM, and this
stack plans without credentials (deliberately). So `check
"cmk_needs_boundary_kms"` raises a plan-time **warning** whenever a boundary and
a CMK are combined, naming the keys. It is a warning, not a gate, because a
correctly-written boundary is a perfectly good configuration — but it is not
silent, which is the point.

## How the app role is assumed

`var.trust_mode` decides, and it is validated at plan time so an operator cannot
end up with a role no workload can assume.

| mode | what it trusts | needs |
|---|---|---|
| `irsa` (**default**) | `sts:AssumeRoleWithWebIdentity` from the EKS cluster's OIDC provider, `aud` = `sts.amazonaws.com`, `sub` = `system:serviceaccount:<namespace>:<serviceaccount>` | `var.eks_oidc_provider_arn` |
| `ec2` | `sts:AssumeRole` from `ec2.amazonaws.com` — the non-Kubernetes case, where the app runs on the compute primitive | nothing |

Both conditions are `StringEquals`, never `StringLike`: a wildcarded `sub` would
hand the app's role to every pod in the cluster. The namespace and
ServiceAccount default to the app name, which is exactly what
[`app-deploy`](../app-deploy) creates; override with `var.k8s_namespace` /
`var.k8s_service_account` if the deploy stack overrides its namespace.

Get the provider ARN from the cluster:

```sh
aws eks describe-cluster --name <cluster> --query cluster.identity.oidc.issuer --output text
# https://oidc.eks.<region>.amazonaws.com/id/<hash>  ->
# arn:aws:iam::<account>:oidc-provider/oidc.eks.<region>.amazonaws.com/id/<hash>
aws iam list-open-id-connect-providers
```

**This is a required input for the flagship path.** A factory stack that sets
neither `TF_VAR_eks_oidc_provider_arn` nor `TF_VAR_trust_mode=ec2` now fails at
plan with a message naming both fixes. That is deliberate: the previous EC2-trust
default produced a role that IRSA could never assume, and failing loudly beats
minting a credential path that silently doesn't work.

## Outputs

| output | what it is |
|---|---|
| `resource_access` | map `"<primitive>/<name>"` => the module's `access` object — **sensitive** |
| `resource_ids` | same keys => primary id (ARN / resource id) — **sensitive**: it carries secret and database ARNs plus the account ID |
| `resource_keys` | sorted list of resource keys, no identifiers — the safe inventory view for logs and dashboards |
| `app_role_arn` | the aggregated app IAM role |
| `app_role_trust` | trust mode and, for IRSA, the exact namespace, ServiceAccount, `sub` and `aud` the trust policy pins |
| `posture` | which CMK each resource actually got (empty = the AWS-managed key), the access-log destination, and whether `demo_teardown` is on — the audit view, since a control nobody can see the state of is the same problem as one nobody can reach |

This is exactly what the k8s deploy rung consumes: wire `app_role_arn` to the
ServiceAccount annotation, `resource_access` entries to container env, and
`app_role_trust.namespace` to the deploy stack's namespace.

## Try it (no apply needed)

```sh
terraform init -backend=false
terraform validate

# Minimum a stack must set. Missing ones fail at plan naming the fix, not later
# as an opaque policy denial.
export TF_VAR_environment=dev                      # Environment tag / env lane
export TF_VAR_eks_oidc_provider_arn=arn:aws:...    # or TF_VAR_trust_mode=ec2
# Owner comes from the list's `owner:`, or TF_VAR_owner.

terraform plan   # requires cloud credentials; do not apply from a laptop
```

Operator switches, all defaulted off:

| variable | effect |
|---|---|
| `TF_VAR_allowed_kms_key_arns` | JSON list of CMKs a shopping list may name. Empty = none, and any `kms_key_arn:` is rejected |
| `TF_VAR_default_kms_key_arn` | CMK for every resource that names none |
| `TF_VAR_access_log_bucket` | S3 access-log destination for every vended bucket |
| `TF_VAR_demo_teardown` | give up deletion protection / final snapshot / recovery windows so a demo env can be destroyed |
