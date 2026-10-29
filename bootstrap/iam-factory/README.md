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
| 3 | [`roles/`](../../roles) | platform admin, root-admin key |

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
| `worker_pool_id` | private `elevated-engines` pool | co-tenant runs on shared workers widen the credential-theft surface |
| `enable_well_known_secret_masking` | `true` | runs carry an elevated token |
| labels | `platform-factory`, `elevated` | `elevated` marks stacks that run with elevated credentials |

## Known gap: inheritance

`platform-admin` and the vended service Spaces use `inherit_entities = true`, so vended Spaces
inherit everything `root` holds. The factory can't change that: disabling inheritance is
root-admin-only, and the factory runs with Space-admin. Setting it to `false` would also cut vended
stacks off from the root-level AWS integration, worker pool and policies.

The fix is to create the AWS integration in `platform-admin` instead of `root`, then set
`var.inherit_entities = false` here. The integration is created outside this repo today.
