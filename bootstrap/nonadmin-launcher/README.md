# bootstrap/nonadmin-launcher

The **platform team's** IaC for the "non-admin launcher" pattern. It provisions everything a product
team needs to self-serve governed onboarding **without ever holding Space Admin**.

## Two layers, don't confuse them

| Directory | Who owns it | What it is |
|---|---|---|
| `bootstrap/nonadmin-launcher/` (this) | Platform team, **root admin** | Creates the Spaces, the engine stack, and the **role binding** (the elevation). |
| `patterns/nonadmin-launcher/engine/` | Platform team | The Terraform the engine stack **runs** — reads a shopping list and creates `app-stack-*` inside the team Space. |

## What it creates

1. Spaces `platform` (governance) and `<team_name>` (product team), both under `root`.
2. Stack `onboarding-engine` in `platform`, tracking this repo's
   `patterns/nonadmin-launcher/engine/`. It does **not** set the legacy `administrative` attribute —
   the API removed it (disabled June 1, 2026). The stack has no intrinsic privilege at all; the
   **role binding** below is the sole elevation mechanism.
3. `spacelift_role_attachment` binding the system **Space admin** role (resolved by its
   `space-admin` slug, overridable via `var.space_admin_role_id`) to the *engine stack*, scoped to the
   team Space. **This one object is the entire elevation** — the engine's runs get Space-admin on the
   team Space, independent of who triggers them.

## Hardening posture of the engine stack

| control | value | why |
|---|---|---|
| `autodeploy` | `false` | every run pauses at the sign-off gate |
| `protect_from_deletion` | `true` | the elevation must not be deletable by accident |
| `worker_pool_id` | private `elevated-engines` pool | co-tenant runs on shared workers widen the credential-theft surface (backlog item 5) |
| `enable_well_known_secret_masking` | `true` | runs carry an elevated token |
| labels | `engine`, `poc:nonadmin-launcher`, `elevated` | `elevated` is the marker `bootstrap/governance` audits |

## Team roles moved to `roles/`

This root used to create a `<team>-consumer` role holding `SPACE_READ` + `RUN_TRIGGER` +
`RUN_CONFIRM`. That is the self-approvable combination backlog item 2 exists to kill, so it is gone.
[`roles/`](../../roles) now owns the `requester` / `approver` split, binds it to IdP groups, and fails
its own plan if a group holds both halves.

Bind it to `platform_space_id`: role attachments are **Space-scoped** (there is no stack-scoped human
binding — `stack_id` on an attachment makes the *stack* the subject, which is the elevation
mechanism), and the `platform` Space holds exactly one stack. So a `requester` bound there can trigger
the engine and nothing else. That is the confinement the old commented-out attachment was reaching
for; it just needed Space topology rather than a `stack_id` + `idp_group_mapping_id` combination the
API rejects as two subjects.

## Why the governance plane inherits

`platform` is created with `inherit_entities = true` (it was `false`). Entity inheritance is the
transport for **governance**, not only for credentials: with it off, neither the private worker pool
nor the root-published policy set can reach the engine stack — the most privileged object in the
account would run on shared workers with no PLAN, GIT_PUSH or APPROVAL policy attached.

The trade: `platform` now also inherits root's cloud integrations. That is acceptable because the
Space holds only admin-owned engine stacks and the engine already has Space-admin on the team Space.
The **team** Space, where team-authored code actually runs, stays `inherit_entities = false` — that is
where leakage would matter. Governance reaches it by publishing the policy set directly into it: add
`team_space_id` to `bootstrap/governance`'s `policy_spaces`.

If you need `platform` isolated too, set `platform_space_inherit_entities = false` and give that Space
its own worker pool (`worker-pools/` with `space_id`) plus its own policy publication. The plan checks
that combination and fails if the pool would be unreachable.

## This must run as root admin — by design

Creating roles and attaching Space Admin both require **root-admin** privileges (you can't grant a
role you don't hold). That's the deliberate anti-escalation boundary. Apply this as a root-admin
identity:

- as an **administrative stack in `root`** (role-bind Space admin @ root to it), or
- via a **blueprint the platform team deploys**, or
- locally with `SPACELIFT_API_KEY_*` for a root-admin API key.

Product-team users never run this. They get the `requester` role and trigger the engine.

## Apply order

`worker-pools/` → **this root** → `bootstrap/governance/` → `roles/`. The worker pool must exist
first: this root resolves it by name and the plan fails if it does not, rather than letting an
elevated token fall back to shared workers.

```bash
cp terraform.tfvars.example terraform.tfvars   # then edit
export SPACELIFT_API_KEY_ENDPOINT=https://<your-account>.app.spacelift.io
export SPACELIFT_API_KEY_ID=...      # root-admin key
export SPACELIFT_API_KEY_SECRET=...
terraform init && terraform apply
```

Then trigger `onboarding-engine` once (UI or `spacectl`). It plans, waits at the sign-off gate, and on
confirm creates the app stacks in the team Space.

## Onboarding another team

Copy this root with a new `team_name`, or refactor the team-specific pieces (`spacelift_space.team`,
the engine stack, the binding) into a module and `for_each` over a map of teams.
