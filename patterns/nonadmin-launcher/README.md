# Pattern: non-admin launcher

Product teams self-serve stack provisioning **without ever holding Space
Admin**. The privilege lives on a stack, not on any person.

## Why not just let the team deploy a Template that grants the elevation?

This is the question that motivates the whole pattern. The intuitive design —
a product-team user deploys a governed Template/Blueprint into their Space, and
the Template attaches Space Admin to the launcher stack — **cannot work, by
design**:

- A Blueprint runs with the **deploying user's** permissions, and Spacelift
  enforces that you cannot grant a role you do not hold. So a Template that
  attaches Space Admin requires the deployer to already *be* Space Admin.
- You cannot safely hand product teams Space Admin: it also grants
  `STACK_UPDATE`, letting them edit the `env:*` labels that policy guardrails
  depend on — i.e. bypass the guardrails.
- There is no narrower permission that allows creating a role binding without
  that label/space power, and there shouldn't be: **granting authority is
  inherently privileged.** If a non-admin could deploy a Template that grants
  admin to a stack, they could edit that Template (or its inputs) to elevate
  themselves. The check is the anti-escalation boundary working correctly.

**The resolution is to decouple *creating* the elevation from *using* it.** The
elevation is created **once, by an admin** (`bootstrap/`), and bound to the
launcher *stack* — not to any user. Product-team users never deploy the
privileged object; they only **trigger** the pre-elevated stack. The deploying
identity is never the thing that creates the elevation, so it never needs the
elevated permission.

## How it works

1. The platform team (root admin) runs `bootstrap/nonadmin-launcher/` **once
   per team**. It creates a governance Space (`platform`), the team's Space,
   the admin-owned **engine stack**, and the single privileged object: a
   `spacelift_role_attachment` binding the system **Space admin** role to the
   *engine stack*, scoped to the team's Space.
2. The engine stack tracks `patterns/nonadmin-launcher/engine/` (this
   directory) — admin-owned Terraform that reads a shopping list and vends
   `app-stack-*` into the team Space. Its runs receive a short-lived injected
   `SPACELIFT_API_TOKEN` carrying exactly the team-Space-scoped admin
   permission from the role binding, independent of who triggered the run.
3. Product-team users hold only a non-admin consumer role
   (`SPACE_READ` + `RUN_TRIGGER` + `RUN_CONFIRM`), attached **stack-scoped to
   the engine stack only** — they can trigger and confirm this one governed
   entry point, nothing else in the `platform` Space. No `SPACE_ADMIN`, no
   `STACK_UPDATE`, so they cannot edit labels or attach roles.

A note on the deprecated `administrative` flag: the engine stack does **not**
use it — the attribute has been removed by the API (disabled June 1, 2026).
The role binding is the mechanism, and it is the supported replacement.

## Layout

| Directory | What it is |
|---|---|
| `engine/` | The Terraform the engine stack runs. Teams never edit it. |
| `engine/app-example/` | Placeholder workload the vended app stacks track. |
| `../../bootstrap/nonadmin-launcher/` | The root-admin, one-time provisioning of Spaces, engine, binding, and roles. |

## The trust chain

- **Who can change what the engine does?** Only whoever can merge to this
  repo's tracked branch — the engine executes admin-owned code; teams supply
  inputs (the shopping list) only.
- **Who can make the engine act?** Only holders of the consumer role, and only
  via `RUN_TRIGGER`; `autodeploy = false` parks every run at a confirm gate.
- **What can a run do at most?** Space-admin inside the one team Space the
  binding is scoped to. It cannot touch `root`, sibling teams, or the
  `platform` Space itself.

## Current limitations (PoC)

The shopping list is a `list(string)` Terraform variable fed in by the
bootstrap, not yet a git-tracked YAML declaration like `patterns/iam-factory`'s
`services/`. Moving it to reviewed-in-git data is a documented next step — see
[`docs/hardening-backlog.md`](../../docs/hardening-backlog.md) for that and the
other deferred hardening items (branch protection, approval/push/plan policies,
private worker pool). Read the full design rationale in
[`docs/nonadmin-launcher-privilege-memo.md`](../../docs/nonadmin-launcher-privilege-memo.md).
