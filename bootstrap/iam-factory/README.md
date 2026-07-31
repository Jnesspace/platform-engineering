# bootstrap/iam-factory

Root-admin, one-time. Stands up the credential-vending plane: the `platform-admin` Space, the
`iam-factory` stack, and **the elevation** — `spacelift_role_attachment` binding the system
`space-admin` role to that *stack*, scoped to `platform-admin`. A developer who triggers the stack
exercises Space-admin without ever holding it.

The Terraform the stack *runs* lives in [`patterns/iam-factory`](../../patterns/iam-factory). Don't
confuse the two layers.

## Who runs it, with what, in what order

| # | root | who |
|---|---|---|
| 1 | [`worker-pools/`](../../worker-pools) | platform admin, root-admin key |
| 2 | **this root** | platform admin, root-admin key |
| 3 | [`bootstrap/governance/`](../governance) | platform admin, root-admin key |
| 4 | [`roles/`](../../roles) | platform admin, root-admin key |

Step 1 first: this root resolves the private worker pool **by name** and the plan fails if it does
not exist, rather than letting an elevated token land on shared workers. Creating roles and attaching
Space-admin both require root admin — you cannot grant a role you do not hold. That is the deliberate
anti-escalation boundary, and it is why product-team users never run this.

```sh
cp terraform.tfvars.example terraform.tfvars   # then edit
export SPACELIFT_API_KEY_ENDPOINT=https://<your-account>.app.spacelift.io
export SPACELIFT_API_KEY_ID=...      # root-admin key
export SPACELIFT_API_KEY_SECRET=...
terraform init && terraform apply
```

## Hardening posture of the factory stack

| control | value | why |
|---|---|---|
| `autodeploy` | `false` | every run pauses at the sign-off gate |
| `protect_from_deletion` | `true` | the elevation must not be deletable by accident |
| `worker_pool_id` | private `elevated-engines` pool | co-tenant runs on shared workers widen the credential-theft surface (backlog item 5) |
| `enable_well_known_secret_masking` | `true` | runs carry an elevated token |
| labels | `platform-factory`, `elevated` | `elevated` is the marker `bootstrap/governance` audits |
| PLAN / GIT_PUSH / APPROVAL / TRIGGER policies | auto-attached from `root` | see [`bootstrap/governance`](../governance) |

## Inheritance and hardening item 7

`spacelift_space.platform_admin` is created with `inherit_entities = true`, and
[`patterns/iam-factory`](../../patterns/iam-factory) creates its vended service Spaces as children
of it, also with `inherit_entities = true`. Backlog item 7 asks for `false`. Here is the honest state
of that.

**Why the factory cannot do it.** Disabling inheritance is a root-admin-only operation and the
factory deliberately runs with Space-admin. That is the anti-escalation boundary working as designed:
the factory cannot loosen *or tighten* the Space hierarchy it provisions into.

**Why bootstrap cannot do it either.** Bootstrap does not own the vended Spaces — the factory
creates them, one per `services/*.yaml`, and they live in the factory stack's state. For this root to
set `inherit_entities = false` on them it would have to `terraform import` resources another root
manages, and then the two roots fight forever: the factory's next run sets `true`, this root's next
run sets `false`.

**Why `false` is not a free win anyway.** Inheritance is all-or-nothing and it is the transport for
*governance*, not just credentials. Setting `inherit_entities = false` on a vended Space cuts it off
from:

- the root-level AWS integration the vended stacks deploy with,
- the private `elevated-engines` worker pool,
- the entire root-published policy set (PLAN / GIT_PUSH / APPROVAL / TRIGGER).

So the naive tighten trades a credential blast radius for a governance blast radius, and the second
one is worse: the stacks keep their credentials (attached directly) and lose their guardrails.

**What actually closes it.** The root cause is that `root` holds both credentials (the AWS
integration) and governance (policies, worker pool), so no single inheritance setting is correct. The
fix is to stop mixing them:

1. Create the AWS integration **in `platform-admin`** instead of `root` (`spacelift_aws_integration`
   takes a `space_id`). It is created out-of-band today, so this repo cannot do it.
2. Then set `inherit_entities = false` on `platform-admin` — this root's `var.inherit_entities`
   already exposes that lever — so nothing leaks down from `root`.
3. Keep vended Spaces at `inherit_entities = true` so they inherit exactly the `platform-admin`
   subtree: that one integration, and nothing else.
4. Publish the governance policy set into `platform-admin` as well, by adding it to
   `bootstrap/governance`'s `policy_spaces`.

That contains the leak to the admin-plane subtree without severing governance, and every step is a
root-admin operation in this layer. Step 1 is the blocker and it is outside this repo.

**Status: item 7 is NOT closed.** The lever now exists in the right layer, and the residual gap is
precisely: *vended service Spaces inherit the `platform-admin` subtree, which today includes
everything `root` holds.* Closing it needs the AWS integration moved out of `root` (above), or a
restructure of `patterns/iam-factory` so that root-admin bootstrap pre-creates the service Spaces and
the factory only vends an IAM role into a Space it is handed — at which point `inherit_entities`
belongs to bootstrap and the whole problem disappears.
