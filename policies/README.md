# Spacelift Policy Library

Standalone, attachable Spacelift policies (`package spacelift`, Rego v1). Every file is published
and attached by `bootstrap/governance/`, which derives the Spacelift policy type from the
**directory name** — so `policies/plan/foo.rego` becomes a `PLAN` policy. Adding a `.rego` to the
right directory is the whole procedure.

Each policy declares its tunables as constants at the top. Adjust those, not the rule bodies.

## The policies

**Enforcing** = a positive result stops the run or blocks the action. **Advisory** = it prints and,
for `warn` on a tracked run, pushes the run to *Unconfirmed* for a human, but never fails it.

| file | type | what it does | attach to | mode |
| --- | --- | --- | --- | --- |
| `plan/cap-new-resources.rego` | PLAN | Two blast-radius fuses for a runaway `for_each`: 25 cloud resources, 75 Spacelift control-plane objects. Counted separately, so control-plane volume never buys infrastructure headroom | every stack | enforcing |
| `plan/deny-privileged-iam.rego` | PLAN | Denies create **and update** of `spacelift_role`, `spacelift_role_attachment`, `spacelift_user`, `spacelift_api_key`, `spacelift_idp_group_mapping`; denies creating IAM users, login profiles, and access keys. Exempts the bootstrap layer by `project_root`, not by label | `*` — self-exempts on `project_root` | enforcing |
| `plan/enforce-required-tags.rego` | PLAN | Denies resources created/updated without `Environment`, `Project`, `Owner`. Reads `tags_all`, `tags` and `labels`, so it covers AWS, Azure and GCP | every stack | enforcing |
| `plan/protect-env-labels.rego` | PLAN | Denies `env:*` label changes on `spacelift_stack` — those labels are the promotion lanes and drive policy auto-attachment | stacks that manage other stacks (`bootstrap/environments`, the launcher engine) | enforcing + 1 advisory |
| `plan/launcher-engine-guardrail.rego` | PLAN | **Backlog #4.** Caps what a `nonadmin-launcher` run may produce: only `spacelift_stack` and its own `terraform_data` gates, one target Space, never `root`, never a `bootstrap/` project root, ≤10 stacks, name pattern, required provenance label, no privileged labels, no `autodeploy`, no roles/Spaces/policy attachments | `*` — self-gates on the `engine` / `poc:nonadmin-launcher` label | enforcing + 2 advisory |
| `plan/iam-factory-guardrail.rego` | PLAN | **Backlog #6 (shape).** Caps what an `iam-factory` run may produce: resource-type allowlist, no role/policy/stack creation, ≤10 Spaces, no Space parented at `root`, no `inherit_entities = false`, role-name pattern, `autoattach:` label allowlist, Spacelift-only OIDC audience | `*` — self-gates on the `platform-factory` label | enforcing |
| `plan/iam-factory-trust-boundary.rego` | PLAN | **Backlog #6 (IAM documents).** Reads the actual JSON: denies a substituted or weakened permissions boundary, a trust policy whose OIDC `sub` is not pinned to one Space, a non-Federated principal, an assume action other than `sts:AssumeRoleWithWebIdentity`, off-catalog `iam:`/`organizations:`/`account:`/`sts:` grants, and `NotAction` | `*` — self-gates on the `platform-factory` label | enforcing + 2 advisory |
| `push/track-intended-changes.rego` | GIT_PUSH | The only policy that **grants** runs: tracks pushes to the stack's branch inside its project root (or `additional_project_globs`), proposes PRs aimed at that branch, ignores the rest and all tags | every stack | required |
| `push/ignore-untrusted-authors.rego` | GIT_PUSH | Restrictive only. Ignores PRs from authors outside `trusted_authors` and PRs whose head branch lives in a fork, and marks the VCS check red | every stack, alongside `track-intended-changes` | enforcing |
| `push/proposed-run-safety.rego` | GIT_PUSH | **Backlog #3.** Restrictive only. On elevated stacks, withholds the proposed run when the PR is a draft or unapproved, or when it edits `.spacelift/` or `*.custom.spacelift.json` — the plan-time RCE paths | `*` — self-gates on the `engine` / `platform-factory` / `elevated` label | enforcing |
| `approval/require-approval.rego` | APPROVAL | The account's **only** APPROVAL policy. On `UNCONFIRMED` runs and tasks: one approval on any stack, two distinct approvers on `env:prod`, and in both cases at least one approver who is neither the run's creator nor its triggerer. Machine-created runs (no login) need two. Any rejection blocks | every stack | enforcing |
| `login/map-idp-groups.rego` | LOGIN | Account members and machine sessions may log in; the `platform-engineering` group logs in as account admin; other groups get `space-admin` on their `team:<name>` Space and `space-reader` on `shared` Spaces | account-global — existing in the right Space *is* the wiring | enforcing |
| `trigger/trigger-dependencies.rego` | TRIGGER | After a successful tracked run, triggers every stack labeled `depends-on:<this stack id>`, never itself | every stack | orchestration, not a gate |
| `notification/notify-failed-runs.rego` | NOTIFICATION | Routes failed non-proposed runs to Slack with a run link | evaluated per Space; no stack attachment | routing, not a gate |
| `access/team-space-access.rego` | ACCESS | Write on stacks/modules labeled `team:<name>`, read on `visibility:org` | **never published — see below** | retired |

## Read this before trusting the table

**`access/team-space-access.rego` is retired, and `bootstrap/governance` now refuses to publish
it.** Spacelift removed stack access, task and initialization policies on 2026-05-30 and states that
creating one is disabled account-side. The Terraform provider still accepts `ACCESS` in its `type`
enum, so this only fails against a live API — which is why the delivery plane skips it by name
(`local.retired_types`) and reports it in `output.skipped_policies` rather than trying and failing.
The file stays on disk because the pattern is worth recording; the live equivalent is the `roles`
rule in `login/map-idp-groups.rego`.

**The advisory rules, explicitly.** These print but never stop a run:

| policy | advisory rule | why it is not a deny |
| --- | --- | --- |
| `plan/protect-env-labels.rego` | new stack labels unknown at plan time | Terraform omits unknown values from `after`, so a deny would fail legitimate runs; a `warn` forces a human look instead |
| `plan/launcher-engine-guardrail.rego` | vended stack created without `protect_from_deletion` | a hygiene default, not a privilege boundary |
| `plan/launcher-engine-guardrail.rego` | vended stack being deleted | offboarding is legitimate; it just should not be a surprise |
| `plan/iam-factory-trust-boundary.rego` | role has no `permissions_boundary` in the plan | on the first factory apply the boundary ARN genuinely is not knowable yet. Every later run has it in state, where the deny applies |
| `plan/iam-factory-trust-boundary.rego` | role has no `assume_role_policy` in the plan | vending into a **new** Space leaves the document unknown, because it embeds the Space ID |

Both `iam-factory-trust-boundary` advisories are the honest limit of a plan-time check: the values
are unknowable on a first apply, so the policy says so rather than pretending. They harden into
denies on every subsequent run.

**Attachment rules that matter.**

- **There is exactly one APPROVAL policy, and that is the fix.** Spacelift **OR**-combines policies
  of the same type on a stack, so a second APPROVAL policy can only ever weaken the first. The
  previous pair (`deny-self-approval` + `require-prod-approval`) was broken in both directions, as
  measured by evaluating each file in isolation the way Spacelift does and OR-ing the results: on a
  non-prod stack `require-prod-approval`'s `approve if not is_prod` returned `true` with zero
  reviews, so self-approval sailed through everywhere; on `env:prod`, `deny-self-approval` returned
  `true` on a single independent approval, so the two-approver quorum collapsed to one. Scoping does
  not fix it — leaving the broad policy at `*` still lands both on prod, and narrowing it to `env:*`
  labels leaves every unlabelled stack with no APPROVAL policy at all. Merging was the only option
  that keeps `*` coverage and a defined quorum.
- **`push/ignore-untrusted-authors.rego` and `push/proposed-run-safety.rego` never grant runs.**
  They only ever `ignore`. Spacelift ignores a push if *any* attached policy says ignore, which is
  why a restrictive companion policy composes safely. Attached alone, though, nothing ever runs —
  `track-intended-changes.rego` must be attached too.
- **`plan/deny-privileged-iam.rego` is safe at `*`, including on the bootstrap roots.** It exempts
  runs whose `input.spacelift.stack.project_root` sits under `bootstrap/`. That field is a *stack
  setting* held in the Spacelift control plane, so repo content cannot change it — unlike
  `input.spacelift.run.runtime_config.project_root`, which `.spacelift/config.yml` can override and
  which `push/proposed-run-safety.rego` already treats as a plan-time RCE path. Labels appear only
  in the revoking direction (`engine`, `poc:nonadmin-launcher`, `platform-factory`, `app-factory`
  disqualify), so the one thing a stack can influence about itself can only ever *lose* it the
  exemption. `plan/launcher-engine-guardrail.rego` closes the last route by denying a vended stack
  whose `project_root` starts with `bootstrap/`. The AWS half of the policy — long-lived access
  keys — is not exempted for anyone.
- No policy in this library defines `allow_fork`. Without one, Spacelift refuses to run forked pull
  requests at all — keep it that way.

**Account-specific values are substituted at publish time, not edited here.**

No `.rego` in this library contains an account identifier. The two policies that need one ship a
placeholder shaped like the value that replaces it, and `bootstrap/governance` substitutes it from a
typed variable while publishing:

| policy | placeholder | variable | if unset |
| --- | --- | --- | --- |
| `notification/notify-failed-runs.rego` | `REPLACE_WITH_SLACK_CHANNEL_ID` | `slack_channel_id` | the policy is **not published** — a wrong channel ID fails silently, so shipping one is worse than shipping none |
| `push/ignore-untrusted-authors.rego` | `"replace-with-trusted-authors"`, `replace-with-repo-owner` | `trusted_pr_authors`, `repo_owner` | the plan **fails** — this one is enforcing, and unsubstituted it fails closed (every PR ignored) |

The placeholders are ordinary Rego string literals, so `opa test policies/` runs each file
standalone and both the placeholder and the substituted form pass `opa check --strict`. Tests take
the values from the policy's own constants rather than restating them, so a fixture cannot drift out
of step with what gets published.

**Constants still set in-file.** These are structural, not account identifiers:

| policy | constant | today |
| --- | --- | --- |
| `plan/cap-new-resources.rego` | `max_new_resources`, `max_new_control_plane` | 25 and 75 |
| `plan/deny-privileged-iam.rego` | `bootstrap_project_roots` | `bootstrap/`; keep in step with `launcher_forbidden_project_roots` |
| `plan/launcher-engine-guardrail.rego` | `launcher_allowed_space_ids` | empty, so the Space pin is off. Structural checks still apply |
| `plan/iam-factory-guardrail.rego` | `factory_allowed_parents` | empty, so the parent-Space pin is off. `root` is still denied |

## Tests

`opa test policies/` — 173 tests, one file per policy under `policies/<type>/tests/`.

Tests live in a `tests/` subdirectory on purpose: `bootstrap/governance/` discovers policies with
`fileset(policies_dir, "*/*.rego")`, which does not match a second directory level, so test files
are never published as Spacelift policies.

Two things to know before adding tests:

1. **Spacelift evaluates each policy file in isolation; `opa test` merges them all** into one
   `data.spacelift`. So `deny` is the union of all seven PLAN policies, and `ignore` is the OR of
   all three GIT_PUSH policies. Assert on a policy's own `deny` message substring, or on its own
   uniquely-named helper rules — never on `count(deny) == 0`. Boolean rules need fixtures that
   determine every contributing policy; the existing tests do this and say so in comments.
2. **The merge also constrains rule names.** A boolean `deny` in a LOGIN or ACCESS policy will not
   compile alongside the PLAN policies' set-valued `deny`. That is why
   `login/map-idp-groups.rego` has no explicit `deny` rule — the login default is already deny.

Two Rego traps the tests exist to catch, both of which silently disable a rule rather than erroring:

- `not is_array(x.y.z)` is **not** true when `z` is absent. OPA hoists the nested reference out of
  the negation, so the whole body goes undefined. Use `not is_array(object.get(x, ["y","z"], null))`.
- `spacelift.foo with input as fixture == expected` parses the comparison into the `with` term and
  asserts nothing. Assign through a helper function first.
