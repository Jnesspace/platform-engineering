# bootstrap/nonadmin-launcher

The **platform team's** IaC for the "non-admin launcher" pattern — the
declarative version of the live PoC. It provisions everything a product team
needs to self-serve governed onboarding **without ever holding Space Admin**.

## Two layers, don't confuse them

| Directory | Who owns it | What it is |
|---|---|---|
| `bootstrap/nonadmin-launcher/` (this) | Platform team, **root admin** | Creates the Spaces, the engine stack, the **role binding** (the elevation), and the team's non-admin role. |
| `patterns/nonadmin-launcher/engine/` | Platform team | The Terraform the engine stack **runs** — reads a shopping list and creates `app-stack-*` inside the team Space. |

## What it creates

1. Spaces `platform` (governance) and `cpe-team1` (product team), both under `root`.
2. Stack `onboarding-engine` in `platform`, tracking this repo's
   `patterns/nonadmin-launcher/engine/`. It does **not** set the legacy
   `administrative` attribute — that attribute has been removed by the API
   (disabled June 1, 2026). The stack has no intrinsic privilege at all; the
   **role binding** below is the sole elevation mechanism.
3. `spacelift_role_attachment` binding the system **Space admin** role
   (resolved by its `space-admin` slug, overridable via
   `var.space_admin_role_id`) to the *engine stack*, scoped to `cpe-team1`.
   **This one object is the entire elevation** — the engine's runs get
   Space-admin on `cpe-team1`, independent of who triggers them.
4. Role `cpe-team1-consumer` (`SPACE_READ` + `RUN_TRIGGER` + `RUN_CONFIRM`) —
   no `SPACE_ADMIN`, no `STACK_UPDATE`, so holders can't touch `env:*` labels
   or attach roles. The (commented) attachment binding it to the team is
   **stack-scoped to the engine stack only** — the team gets trigger rights on
   just that one governed entry point, not on everything in the `platform`
   Space.

## This must run as root admin — by design

Creating roles and attaching Space Admin both require **root-admin** privileges
(you can't grant a role you don't hold). That's the deliberate anti-escalation
boundary. So apply this as a root-admin identity:

- as an **administrative stack in `root`** (role-bind Space admin @ root to it), or
- via a **blueprint the platform team deploys**, or
- locally with `SPACELIFT_API_KEY_*` for a root-admin API key.

Product-team users never run this. They only get the `*-consumer` role and
trigger the engine.

## Apply

```bash
export SPACELIFT_API_KEY_ENDPOINT=https://jnesspace.app.spacelift.io
export SPACELIFT_API_KEY_ID=...      # root-admin key
export SPACELIFT_API_KEY_SECRET=...
terraform init
terraform apply
```

Then trigger `onboarding-engine` once (UI or `spacectl stack local-preview`/run).
It plans, waits at the sign-off gate, and on confirm creates the app stacks in
the team Space.

## Onboarding another team

Copy this root with a new `team_name`, or refactor the team-specific pieces
(`spacelift_space.team`, the engine stack, the binding, the consumer role) into
a module and `for_each` over a map of teams.
