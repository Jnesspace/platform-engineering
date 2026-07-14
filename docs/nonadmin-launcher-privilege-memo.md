# Design Memo: Non-Admin Blueprint Deployment of Privileged Launcher Stacks

**For:** Customer call — governed onboarding Template / launcher ("common engine") architecture
**Account context verified against:** `jnesspace.app.spacelift.io`, Spacelift docs, `spacelift-io/spacelift` provider docs
**Date:** 2026-07-13

---

## TL;DR

**Direct answer to the customer's core question: today, no — there is no supported way for the *act of deploying a Blueprint* to attach permissions the deployer doesn't hold.** The role-binding check is a deliberate anti-privilege-escalation control: creating a stack role binding requires admin on the binding space, full stop. But the goal is achievable by moving the *grant* out of the user-triggered deploy path. Since their common-engine design already solves code governance (the elevated stack runs only admin-owned Terraform; teams supply inputs), two patterns work:

1. **(Recommended) Durable, platform-provisioned engine stack with a Space Admin *stack role binding* on the team's Space.** No stored secret — runs get a short-lived injected token scoped to the binding space and its subtree. Teams interact via inputs only (App-repo declarations + run triggers). The only constraint: the binding must be created by an admin identity (platform team or their own admin "factory" stack), not by the end user's deploy.
2. **(Fallback, if the elevated stack must be user-deployable) Admin-owned Context carrying a *scoped* API key**, consumed ambiently by the `spacelift` Terraform provider. Works independent of the deployer, but introduces a long-lived stored secret with rotation and theft-surface costs.

Either way, enforce `env:*` label integrity as defense-in-depth: with fine-grained RBAC roles, teams don't need any label-mutating action in the first place, and a plan/approval policy can reject runs whose labels don't match an admin-controlled anchor.

One deprecation landmine to raise on the call: **the `administrative` flag was disabled June 1, 2026** and auto-converted to Space Admin role attachments — do not design against it.

---

## 1. Verified facts (and how they were verified)

| Claim | Status | Source |
|---|---|---|
| `spacelift` provider authenticates from env vars `SPACELIFT_API_KEY_ENDPOINT` / `SPACELIFT_API_KEY_ID` / `SPACELIFT_API_KEY_SECRET` (or provider args `api_key_endpoint/id/secret`); inside a Spacelift run it automatically uses the injected `SPACELIFT_API_TOKEN` with zero provider config | **Verified** | Provider docs (index.md): "All Spacelift jobs receive a temporary authentication token in the `SPACELIFT_API_TOKEN`" |
| Creating a **stack role binding** requires admin on *both* the stack's space and the binding space: "To prevent privilege escalation, you must have admin access to both spaces" | **Verified** — this is exactly why their template fails for non-admins | Stack role bindings docs |
| A role bound to a stack grants that stack's **runs** the role's permissions in the binding space **and its child spaces** (subtree) | **Verified** | Same page |
| `administrative` flag: **disabled June 1, 2026**, auto-converted to a Space Admin role attachment on the stack's own space; the Blueprint schema marks `administrative` "Deprecated… it'll be ineffective in the future" | **Verified** | Stack settings docs, Blueprint docs |
| Fine-grained RBAC actions exist for role-binding management (`STACK_ROLE_BINDING_CREATE/UPDATE/DELETE`) and context/policy attach — **but all are marked "Disabled. Do not use." in the live GraphQL schema** | **Verified** via schema introspection on this account | `Action` enum, `jnesspace` GraphQL API |
| A custom role with `STACK_MANAGE` (no `SPACE_ADMIN`) exists and is usable — this account already has such roles ("test2", "test admin") | **Verified** via `roles` query | `jnesspace` account |
| API keys are machine ("virtual") users; they can be given **role bindings scoped to specific spaces** (i.e., an "admin key" can be subtree-scoped, not account-wide) | **Verified** | API docs, API key role bindings |
| Context secret values are write-only ("not visible in the Spacelift UI or via the API"); masked values are redacted in logs | **Verified** (masking is best-effort — see §3) | Context docs, stack settings |
| Plan/approval/push policy inputs include `stack.labels`, `stack.name`, `stack.roles`, `stack.worker_pool` — but **no `stack.space` / space id** | **Verified against current docs** (flagged: docs may lag product) | Plan policy, approval, push policy |

**Could not verify (test before the call or flag on it):**
- Whether Blueprint `attachments.contexts` succeeds when a **non-admin** deploys a template referencing an admin-owned cross-space context (the `STACK_CONTEXT_ATTACH` fine-grained action is also "Disabled" in the schema, so attach may fall back to an admin check just like roles). **This is the make-or-break test for the API-key pattern.**
- Exact behavior of `administrative: true` in a Blueprint deployed post-deprecation (silently ignored vs. converted-with-admin-check). Assume it does not help.
- Blueprint docs still say deploying requires "admin access to the Space where the stack will be created," yet the customer observes non-admins deploying successfully (consistent with RBAC `stack:manage` sufficing, and with the schema's `CREATE_BLUEPRINT_DEPLOYMENT` action). Docs appear to lag RBAC; worth confirming.

---

## 1a. Live-schema test results (run against `jnesspace`, 2026-07-13)

Executed read-only against the account's GraphQL API; these upgrade several "docs say" claims to "schema confirms."

**Attach-type actions are non-grantable — confirmed from the `Action` enum.** Every one of these is present in the enum but flagged `"Disabled. Do not use."`, so they cannot be put into a custom role:
`STACK_ROLE_BINDING_CREATE/UPDATE/DELETE`, `STACK_CONTEXT_ATTACH/DETACH`, `STACK_POLICY_ATTACH/DETACH`, `STACK_AWS_INTEGRATION_ATTACH/DETACH/UPDATE`, `STACK_AZURE_INTEGRATION_*`, `STACK_GCP_INTEGRATION_*`, `STACK_WEBHOOK_*`.
→ **There is no narrower permission for the role binding.** The customer's hunch is correct at the schema level: attaching a role/context/policy/integration to a stack is gated behind `SPACE_ADMIN`, not any assignable fine-grained action.

**Blueprint deployment is its own grantable action.** `CREATE_BLUEPRINT_DEPLOYMENT` (and `TEST_/UPDATE_/ROLLBACK_BLUEPRINT_DEPLOYMENT`, versioned-group actions) are enabled, non-deprecated enum members. This is consistent with the customer's observation that non-admins *can* deploy the template — the deploy itself is permitted; only the embedded **role binding** carries the extra "you must already hold the role" escalation guard.

**Confirmed roles in-account:**
- System **Space admin** = `01JV4Y8CV37PAM16JHB2JHFED5` → `[SPACE_ADMIN, SPACE_READ, SPACE_WRITE]`.
- Custom **`test2`** / **`test admin`** → `STACK_MANAGE` + `STACK_DELETE/LOCK/ENABLE/...` with **no `SPACE_ADMIN`, no `SPACE_WRITE`, and no `STACK_UPDATE`**. Proves a team can hold real stack management without Space Admin and without the label-editing `STACK_UPDATE` action.

**Refines Option B's make-or-break unknown:** because `STACK_CONTEXT_ATTACH` is *also* disabled as a standalone action, attaching the admin-owned key context is `SPACE_ADMIN`-gated *when done directly*. The open question narrows to: does a Blueprint **deploy** (authorized via `CREATE_BLUEPRINT_DEPLOYMENT`) attach a template-declared context without re-checking `SPACE_ADMIN`, the way it evidently does *not* re-check for role bindings? Still requires a genuine non-admin deploy to settle — cannot be reproduced with an admin session.

**Could not run headlessly (need a real non-admin identity; the MCP authenticates as an admin):** tests #1 (non-admin deploy attaching a cross-space context) and #2 (non-admin deploy with `administrative: true`). Test #3 (engine's injected token creating a subtree role binding) requires standing up the Option A reference for real.

---

## 1b. PoC executed live in `jnesspace` (2026-07-13) — Option A confirmed working

The full Option A path, stood up end-to-end via the API. Result: **an engine stack created stacks inside a product team's Space using nothing but a stack role binding — no `administrative` flag, no API key, no stored secret.**

What was built:
- Space `platform` (`platform-01KXENHABYMGMY2C4VAHHNPFVA`) — governance plane.
- Space `cpe-team1` (`cpe-team1-01KXENHC56TC7956BTMJGNS5AV`) — product team Space.
- Stack `onboarding-engine` in `platform`, **`administrative: false`**, tracking `spaces-demo//onboarding-engine` @ `dev` (admin-owned "common engine" code; teams don't edit it).
- **Stack role binding** `01KXENNCJDXBBSR9ENJPAYVVSD`: system **Space admin** role (`01JV4Y8CV37PAM16JHB2JHFED5`) bound to `onboarding-engine`, **binding space = `cpe-team1`**. This is the whole elevation mechanism.
- Non-admin team role `cpe-team-consumer` (`01KXENNDYBTY6HWAZ6WGRS5E1Q`): `[SPACE_READ, RUN_TRIGGER, RUN_CONFIRM]` — no `SPACE_ADMIN`, no `STACK_UPDATE`.

What happened: the engine run planned + applied (parked at `UNCONFIRMED` first — the autodeploy-off sign-off gate — then confirmed). Its injected `SPACELIFT_API_TOKEN` carried Space-admin-on-`cpe-team1` from the binding, so `spacelift_stack.app` created **`app-stack-1`** and **`app-stack-2`** in `cpe-team1`.

**Why this answers the customer's question:** the run's permissions came from the **stack's** role binding, not from whoever triggered the run. A user holding only `cpe-team-consumer` can `RUN_TRIGGER`/`RUN_CONFIRM` this exact engine and get the identical result — creating admin-level stacks in their Space **without ever holding Space Admin**. The one privileged step (creating the engine + binding) is done **once by the platform team**, off the product-team user's path entirely. That's the supported answer that their `attachments.roles`-in-a-user-deployed-template approach was reaching for.

**Still not reproducible headlessly:** whether a *non-admin's own Blueprint deploy* can create the engine+binding (it can't — binding creation needs admin, by design; hence the platform team provisions it). This is the intended division of labor, not a gap.

---

## 2. Why their template fails — and why that's by design

Blueprint `attachments.roles` is sugar for `stackRoleBindingCreate`, and that mutation is evaluated against **the identity performing the deploy**. Granting a stack Space Admin on a space is equivalent to *being* Space Admin there, so Spacelift requires the grantor to already hold it. Any mechanism that let a non-admin deployer mint an admin-bound stack would be a privilege-escalation primitive. The fix is not to weaken the check but to change **whose identity performs the privileged step**.

Also note: the fear driving "we can't give teams Space Admin" is partially dissolved by RBAC itself. Teams never needed Space Admin — a custom role (`SPACE_READ` + `RUN_TRIGGER` + optionally `RUN_CONFIRM`) gives them everything the consumer plane needs *without any label-mutating action* (`STACK_MANAGE`/`STACK_UPDATE` withheld; Space labels always require Space Admin).

---

## 3. The two working patterns

Their common-engine design (admin-owned `sl-onboarding-automation` / `roots/application-stack-provisioning`, published versioned Templates, teams supplying only App-repo environment declarations) already satisfies the critical precondition: **the elevated identity only ever executes admin-owned code.** The classic kill-shot against "stack holding an admin credential" — team pushes malicious Terraform to the launcher — is retired by design. What remains is secret handling, blast radius, and the run-surface around the engine.

### Option A — Durable engine with a stack role binding (recommended)

The platform team (or a root-space "factory" admin stack) provisions, once per team, an engine stack in the governance plane pointing at `sl-onboarding-automation//roots/application-stack-provisioning`, with a role binding: **Space Admin, binding space = the team's Space** (e.g. `M19S513-cpe-team1`). Its runs receive an injected, short-lived `SPACELIFT_API_TOKEN` carrying exactly that subtree-admin permission; the `spacelift` provider inside the run picks it up with an empty `provider "spacelift" {}` block. The engine fans out `app-stack-*`, sub-Spaces (note: creating child Spaces under the team Space is within subtree admin), contexts, and policy attachments.

Team self-service = **inputs only**: merge a PR in the App repo declaring `environments: [d, t, p]` (push webhook or scheduled/drift run triggers the engine), or trigger the engine run directly with a run-scoped role. No user ever deploys anything privileged.

Properties: **zero stored secrets**, token auto-rotates per run, subtree-scoped (cannot touch root or sibling teams), audit attributes actions to the stack identity, fully supported and explicitly positioned as the replacement for `administrative`. The one-time admin provisioning step is the honest cost — and note it can itself be a Blueprint, just deployed by the platform team.

**Do not reach for `administrative: true` to dodge the check.** It is deprecated, was force-converted on June 1, 2026, and even historically it produced the same thing a role binding does (Space Admin over own space + subtree) — there's no reason to believe a non-admin could set it where they can't create the equivalent binding. Unverified edge, but not worth building on.

### Option B — Admin API key in an admin-owned Context (if the elevated stack must be user-deployed / ephemeral)

If the workflow genuinely requires a *non-admin user's Blueprint deploy* to produce the privileged (possibly ephemeral) stack, the template creates a **plain** stack (no `attachments.roles`) and attaches an admin-owned Context containing:

- `SPACELIFT_API_KEY_ENDPOINT = https://jnesspace.app.spacelift.io` (secret: no)
- `SPACELIFT_API_KEY_ID` (secret: yes)
- `SPACELIFT_API_KEY_SECRET` (secret: yes)

The provider then authenticates as the API key's machine user regardless of who deployed — verified provider behavior. Two hard rules:

1. **Never a root-admin key.** Give the key a role binding of Space Admin scoped to the team Space(s) only — API keys support space-scoped role bindings, so the blast radius can match Option A's subtree exactly.
2. **Prefer explicit `attachments.contexts: [{id: ...}]` in the template over `autoattach:` labels.** Auto-attach is label-driven; anyone able to create/label a stack within the context's reachable subtree could self-attach the key context to *their own* stack. With the trusted-engine design the code is safe, but the *context* is only as safe as the set of stacks that can receive it.

Residual costs vs Option A: a long-lived secret at rest (rotation program required — key rotation means updating the context, though that's one place); the key is a billed virtual user; secret masking in logs is best-effort (a five-asterisk redaction defeated by trivial encoding, so treat it as a seatbelt, not a lock); and the unverified question of whether non-admin deployers can even attach a cross-space context (see test item — if that fails, Option B collapses into Option A's "admin must provision" anyway).

**Run-surface hardening for either option** (the engine's identity is usable by anyone who can make it execute): team roles must exclude `TASK_CREATE` (tasks run arbitrary shell commands in the stack's env), `RUN_PROPOSE_WITH_OVERRIDES`, `RUN_TRIGGER_WITH_CUSTOM_RUNTIME_CONFIG`, and `STACK_UPLOAD_LOCAL_WORKSPACE`/`RUN_PROPOSE_LOCAL_WORKSPACE`; keep local preview disabled on the engine; and the engine must consume App repos strictly as *data* (parsed YAML), never as module/source code.

### Decision table

| | A: role-bound engine | B: API key in context |
|---|---|---|
| Stored secret | none | key secret in context |
| Non-admin can create the privileged stack | no (admin provisions once) | yes — if context attach by non-admin verifies |
| Scope | binding space subtree | whatever bindings the key has (can match A) |
| Ephemeral-stack friendly | awkward (each needs an admin-created binding) | natural |
| Vendor posture | first-class replacement for `administrative` | supported provider auth; the *pattern* is a workaround |
| Ongoing ops | none | rotation, virtual-user billing, attach-surface control |

**Recommendation: A**, with the team-facing Template reduced to registration/request artifacts (or dropped entirely in favor of App-repo PRs). Use B only for genuinely ephemeral, user-initiated provisioners — and even then, scoped key + explicit attach.

---

## 4. `env:*` label integrity — defense-in-depth

With the engine design plus run-only team roles, label mutation by teams is already blocked at the RBAC layer (no `STACK_MANAGE`/`STACK_UPDATE`; Space labels need Space Admin). Still, guardrails that *depend* on a mutable attribute should verify it. Because policy inputs expose `stack.labels`, `stack.name`, and `stack.roles` but **not the stack's space**, anchor the check to admin-controlled facts:

```rego
package spacelift

# Auto/explicitly attached to every app stack by the engine.

env_labels := {l | some l in input.spacelift.stack.labels; startswith(l, "env:")}

# Exactly one env label
deny[msg] {
  count(env_labels) != 1
  msg := "stack must carry exactly one env:* label"
}

# Label must match the engine-stamped naming convention (teams cannot rename:
# no STACK_UPDATE), e.g. app-stack-<team>-<env>-...
expected := regex.find_string_submatch_n(`^app-stack-[a-z0-9]+-([dtnsp])-`, input.spacelift.stack.name, 1)[0][1]
deny[msg] {
  not env_labels[sprintf("env:%s", [expected])]
  msg := sprintf("env label does not match provisioned environment %q", [expected])
}
```

Attach it **explicitly by id** from the engine (`attachments.policies` / `policyAttach`), not solely via `autoattach:` labels, so detaching would itself require admin. Add detection: an audit-trail webhook alert on any `stackUpdate`/`spaceUpdate` that touches labels outside the engine identity. Frame on the call: this is belt-and-suspenders now, not the primary control.

---

## 5. Sketch: engine Blueprint (platform-deployed, Option A)

```yaml
inputs:
  - id: team_space_id
  - id: app_repo
stack:
  name: "onboarding-engine-${{ inputs.team_space_id }}"
  space: "${{ inputs.team_space_id }}"          # or a governance sub-space
  vcs:
    repository: "sl-onboarding-automation"
    branch: "main"
    provider: GITHUB   # via managed-github-vcs-integration
  vendor:
    terraform: { workflow_tool: OPEN_TOFU }
  project_root: "roots/application-stack-provisioning"
  attachments:
    roles:
      - role_id: "01JV4Y8CV37PAM16JHB2JHFED5"   # system Space admin role (this account)
        space_id: "${{ inputs.team_space_id }}"
    policies: [ "env-label-integrity" ]
  environment:
    variables:
      - name: TF_VAR_app_repo
        value: "${{ inputs.app_repo }}"
  options: { trigger_run: true }
```

Team surface: PRs to the App repo's environment declaration; engine reads it as data and fans out. For Option B, drop `attachments.roles`, add `attachments.contexts: [{id: onboarding-engine-credentials}]`, and create the scoped API key + context once in the governance space.

---

## 6. Open questions for Spacelift product (worth raising)

1. **`STACK_ROLE_BINDING_CREATE/UPDATE/DELETE` and `STACK_CONTEXT_ATTACH/DETACH` exist in the `Action` enum but are marked "Disabled. Do not use."** — what's the timeline? An enabled, grantable role-binding action (perhaps constrained to a whitelist of roles/spaces) would let Blueprint deployers attach pre-approved roles without Space Admin — the exact missing primitive here.
2. **"Deploy Blueprint as service account"**: a first-class option to run a Blueprint's deploy-time mutations under a designated machine identity (with approval workflow) instead of the deployer. This is the customer's ask, stated generally.
3. **Space id/labels in plan & approval policy inputs** (today only push policy exposes a space, and only under `vcs_integration`). Would make env↔space integrity checks trivial and label-independent.
4. **Policy hook for settings mutations** — no policy type today can gate `stackUpdate`/`spaceUpdate` (label edits); only RBAC and after-the-fact audit webhooks cover it.
5. **`STACK_CREATE` vs `STACK_MANAGE` split** (exists in the enum; public feedback item says they're currently combined) — a create-only grant would narrow what Blueprint deployers can touch.
6. **Clarify Blueprint deploy requirements under RBAC** — docs still say target-space admin, observed behavior suggests `stack:manage` suffices.

---

## Pre-call test list

1. Non-admin deploy of a template with `attachments.contexts` referencing an admin-space context.
2. Non-admin deploy with `administrative: true` (expect ignored or rejected).
3. Engine run creating a role binding in its own subtree via its injected token.
4. Confirm which fine-grained actions are assignable in the roles UI vs the schema enum.

## References

Stack role bindings · RBAC system · API key role bindings · Blueprints · Stack settings / administrative deprecation · Contexts · Plan policy · Approval policy · Push policy · API / API keys · Provider auth docs · Create-stack RBAC feedback item · Live schema/roles introspected on `jnesspace.app.spacelift.io`
