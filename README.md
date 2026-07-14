# platform-engineering

Governed self-service on Spacelift: the platform team owns the guardrails as
code, and product teams get real provisioning power through narrow, audited
entry points — never through admin rights. Every privilege in this repo is
attached to a *stack* or minted from a *catalog*; no person on a product team
holds Space Admin or an IAM credential.

> **Status: PoC.** Not yet production-safe — the deferred security work is
> tracked in **[docs/hardening-backlog.md](docs/hardening-backlog.md)**. Read
> it before deploying beyond a demo account.

## The two patterns

### iam-factory — Space + scoped AWS role vending

One admin stack turns a git-tracked shopping list (`services/*.yaml`) into, per
service: a Spacelift Space, a per-Space IAM role trusted **only by that
Space's OIDC `sub`**, and an auto-attached context handing the role ARN to
labeled stacks. A developer picks permission sets from the platform-owned
`catalog.yaml`; a **plan-time gate blocks anything off-catalog**, and a
permissions boundary hard-caps the role at runtime. Per-Space OIDC trust means
a stack can never assume another Space's role, no matter what ARN it types.

### nonadmin-launcher — self-service provisioning without Space Admin

Product teams trigger an admin-owned **engine stack** that vends app stacks
into their Space. The elevation is a single object: a Space-admin role binding
**on the engine stack**, scoped to the team Space — created once by the
platform team. Runs act with that binding's short-lived injected token,
independent of who triggered them; the gate is git ownership of the engine
code plus an explicit confirm step (`autodeploy = false`). Teams hold only
read + trigger/confirm, stack-scoped to the engine.

## Repo map

```
patterns/
├─ iam-factory/              # code the factory stack runs (catalog, services/, gate, roles)
└─ nonadmin-launcher/
   ├─ README.md              # the pattern, end to end
   └─ engine/                # code the engine stack runs (+ app-example/ workload)
bootstrap/
└─ nonadmin-launcher/        # root-admin, one-time: Spaces, engine stack, the role binding, team role
docs/
├─ nonadmin-launcher-privilege-memo.md   # design memo: why the binding, verified against the API
└─ hardening-backlog.md      # deferred security items — READ THIS
```

**Who owns what:** the platform team owns `bootstrap/` and `patterns/`;
product teams only trigger.
