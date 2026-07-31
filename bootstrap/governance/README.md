# bootstrap/governance — the policy delivery plane

Before this root existed, `grep spacelift_policy` across every `.tf` in the repo returned **zero
hits**: all of [`policies/`](../../policies) was dead weight, which is why hardening backlog items 2,
3, 4 and 6 stayed open even though the `.rego` artifacts were already written. This root turns every
`.rego` into a live, attached Spacelift policy, and then audits that the elevated stacks are actually
covered.

## Who runs it, with what, in what order

Platform admin, **root-admin API key** — policies are account-level objects.

`worker-pools/` → `bootstrap/{iam-factory,nonadmin-launcher,environments}` → **this root** →
`roles/`. It goes after the bootstrap roots because `policy_spaces` takes the Space IDs they output,
and because its audit reads the stacks they create.

```sh
cp terraform.tfvars.example terraform.tfvars   # then edit
export SPACELIFT_API_KEY_ENDPOINT=https://<your-account>.app.spacelift.io
export SPACELIFT_API_KEY_ID=...      # root-admin key
export SPACELIFT_API_KEY_SECRET=...
terraform init && terraform apply
```

## Discovery: adding a `.rego` is the whole procedure

`fileset()` over `policies/*/*.rego`, with the **directory name** as the Spacelift policy type. No
filename list exists to fall out of sync, so renaming or adding a policy file needs no change here.
The glob is exactly one directory deep, so `policies/<type>/tests/*_test.rego` is excluded — OPA unit
tests never get published as policies.

| directory | type | |
|---|---|---|
| `policies/approval/` | `APPROVAL` | |
| `policies/login/` | `LOGIN` | |
| `policies/notification/` | `NOTIFICATION` | |
| `policies/plan/` | `PLAN` | |
| `policies/push/` | `GIT_PUSH` | |
| `policies/trigger/` | `TRIGGER` | |
| `policies/intent/` | `INTENT` | |
| `policies/access/` | `ACCESS` | **retired — never published** |
| `policies/task/`, `policies/initialization/` | `TASK`, `INITIALIZATION` | **retired — never published** |

### Retired types are skipped, not attempted

Spacelift removed stack access, task and initialization policies on **2026-05-30**; the
announcement states plainly that *"creation of new stack access, task, and initialization policies
is disabled"*. The Terraform provider (v1.52.4) still lists all three in the `type` enum, so nothing
fails locally — the **API** rejects them, at apply time, against a live account. So
`local.retired_types` skips publication instead, and `output.skipped_policies` names the file and
the reason. `policies/access/team-space-access.rego` is kept on disk as the record of the pattern;
its live equivalent is the `roles` rule in `login/map-idp-groups.rego`.

(The docs are inconsistent: the deprecated-policies page still shows "to be announced" for task and
initialization while the announcement gives all three the same date. Skipping all three is safe
either way — no policy in this library uses those types, so the only effect is a clear message if
someone adds one.)

`terraform_data.discovery_gate` fails the plan — no credentials needed — when:

1. a `.rego` sits in a directory with no type mapping (so a typo'd directory can't silently ship an
   unattached policy),
2. a policy uses Rego v1 syntax without `import rego.v1` (that import is what selects the `REGO_V1`
   engine; published as `REGO_V0` it parses but never evaluates — a guardrail that silently does
   nothing),
3. a `policy_target_overrides` key names a policy that doesn't exist (catches a rename),
4. a published body still carries a `replace-with-*` / `REPLACE_WITH_*` placeholder (see below).

## Account-specific values: substituted at publish time

Rego takes no Terraform variables, so the values that differ per account used to be literals inside
the `.rego` files — a Slack channel ID and a pinned VCS owner and author list. They are now
placeholders, substituted here from typed variables:

| variable | policy | required? |
|---|---|---|
| `repo_owner`, `trusted_pr_authors` | `push/ignore-untrusted-authors.rego` | **yes** — it is enforcing and attached at `*` |
| `slack_channel_id` | `notification/notify-failed-runs.rego` | no; empty means the policy is **not published** |

The placeholders are ordinary Rego string literals shaped like what replaces them
(`trusted_authors := {"replace-with-trusted-authors"}`), so `opa test policies/` still runs each
file standalone, and both forms pass `opa check --strict`. `replace()` rather than
`templatefile()`: a `${...}` placeholder would make every future `${` written in any policy an
apply-time template error, and it would read as a real value to anyone opening the file.

The two failure modes are handled differently on purpose. An unsubstituted `ignore-untrusted-authors`
fails **closed** (no login matches, every PR is ignored) and the gate refuses to publish it at all.
An unset Slack channel fails **open and silent** — Slack simply drops messages to a channel that
does not exist — so the policy is withheld rather than shipped looking configured.

## Attachment: auto-attach by label, not explicit attachments

Spacelift offers `autoattach:<label>` on the policy and explicit `spacelift_policy_attachment`. This
root uses **only** auto-attach. Reasons, in order of weight:

- **It reaches stacks this root cannot enumerate.** The onboarding engine and iam-factory *create*
  stacks at run time (`app-stack-*`, per-service stacks). Explicit attachments can only cover stacks
  that exist in some Terraform state here; the vended ones would be permanently ungoverned.
- **`autoattach:*` has no opt-out.** A guardrail you have to remember to attach isn't a guardrail. A
  new elevated stack is covered the moment it lands in a reachable Space — there is no label to
  forget.
- **The two mechanisms conflict.** Spacelift allows one attachment per policy/stack pair, so an
  explicit attachment for a pair auto-attach already covers fails the apply. Picking one mechanism
  avoids a whole class of broken applies.

### The coverage matrix

`local.default_autoattach` in `policies.tf`, overridable per type via `var.autoattach_targets` and per
policy via `var.policy_target_overrides`:

| type | default target | why |
|---|---|---|
| `PLAN`, `GIT_PUSH`, `APPROVAL`, `TRIGGER`, `INTENT` | `*` | enforcing types; on by default everywhere |
| `LOGIN` | none | account-global; never attached. Published exactly once, in `root`. |
| `NOTIFICATION` | none | evaluated per Space; existing in a reachable Space *is* the wiring. |

The retired types have no row: there is nothing to attach.

### What covers the elevated stacks

| stack | Space | reached via | policy classes |
|---|---|---|---|
| `iam-factory` | `platform-admin` (inherits root) | root publication | PLAN, GIT_PUSH, APPROVAL, TRIGGER |
| `onboarding-engine` | `platform` (inherits root) | root publication | PLAN, GIT_PUSH, APPROVAL, TRIGGER |
| `app-factory-<env>` | `platform-<env>` (inherits root) | root publication | PLAN, GIT_PUSH, APPROVAL, TRIGGER |
| engine-vended `app-stack-*` | team Space (**does not** inherit) | team Space listed in `policy_spaces` | PLAN, GIT_PUSH, APPROVAL, TRIGGER |
| factory-vended service Spaces | children of `platform-admin` (inherit) | root publication | PLAN, GIT_PUSH, APPROVAL, TRIGGER |

## Spaces: why the policy set is published more than once

A policy is usable only by stacks in its own Space or in Spaces that **inherit entities** from it.
That makes `inherit_entities` the transport for governance, not just for credentials — and
`bootstrap/nonadmin-launcher`'s team Space deliberately has it off. So `var.policy_spaces` takes the
account root **plus every inheritance-isolated Space holding governed stacks**, and the set is
published into each. Policy names are Space-qualified (`deny-self-approval@root`) to stay unique
account-wide.

Do **not** list a Space that already inherits from a listed one: NOTIFICATION policies are evaluated
per Space and would fire twice.

## The audit — the part that makes coverage provable

`terraform_data.elevated_stack_audit` reads every Space and stack in the account and **fails the
plan** if any stack labelled `elevated`:

- has no `worker_pool_id` (backlog item 5 — an elevated token next to co-tenant runs),
- sits in a Space that neither is nor inherits from any `policy_spaces` entry (a published guardrail
  that can never fire),
- has `protect_from_deletion = false`.

`autodeploy` is **reported, not enforced**: `app-factory-dev` autodeploys by design (the promotion
model), so failing on it would be wrong.

Reachability is computed by walking each Space's ancestors while inheritance holds, six levels deep.
Deeper trees under-report reachability, which fails the audit loudly rather than passing it silently.

Outputs, for the one-place-to-look requirement:

| output | answers |
|---|---|
| `published_policies` | every `.rego` → type, Space, Rego engine, autoattach targets, policy ID |
| `skipped_policies` | every `.rego` deliberately **not** published, and why |
| `stack_coverage` | every stack in the account → the policies that actually bind to it |
| `ungoverned_stacks` | the list that should stay empty |
| `elevated_stack_audit` | per elevated stack: worker pool, deletion protection, autodeploy, coverage |

## Known interactions

- **Multiple policies of one type combine permissively.** Spacelift OR-s same-type policies attached
  to one stack, so a second policy can only ever *weaken* the first. This library therefore ships
  **exactly one `APPROVAL` policy** (`approval/require-approval.rego`), which handles both
  self-approval and the `env:prod` two-approver quorum in one decision. The previous pair was
  measurably broken in both directions — see the comment at the top of that file for the evaluated
  result. Scoping cannot fix it: leaving the broad policy at `*` still lands both on prod, and
  narrowing it to `env:*` labels leaves unlabelled stacks with no `APPROVAL` policy at all.
- **`deny-privileged-iam.rego` no longer blocks the bootstrap layer.** It exempts runs whose
  `input.spacelift.stack.project_root` sits under `bootstrap/`, which is a *stack setting* in the
  control plane — not repo content, and not `run.runtime_config.project_root`, which
  `.spacelift/config.yml` can override. Engine labels revoke the exemption, and
  `launcher-engine-guardrail.rego` denies vending a stack into `bootstrap/`, so an engine cannot
  route around it. `bootstrap/*` and `roles/` are safe to run as stacks now, not only locally.
- **This root manages `spacelift_policy`, which no policy blocks.** `spacelift_policy` is absent from
  `deny-privileged-iam.rego`'s blocked types (it is not a privilege grant) but present in both
  engine guardrails' forbidden sets — engines may never mint policies, the governance plane must.
- Editing a policy in the Spacelift UI is overwritten on the next apply. Edit the `.rego`.
