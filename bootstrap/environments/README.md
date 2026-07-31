# bootstrap/environments

Root-admin, one-time: `for_each` over `var.environments` stands up a per-env platform plane — a
`platform-<env>` Space plus an `app-factory-<env>` stack tracking that env's branch. This is the
git-promotion model as code.

## Who runs it, with what, in what order

Platform admin, **root-admin API key**. Apply [`worker-pools/`](../../worker-pools) first — this root
resolves the private pool by name and the plan fails if it does not exist.

`worker-pools/` → **this root** → [`bootstrap/governance/`](../governance) → [`roles/`](../../roles).

```sh
cp terraform.tfvars.example terraform.tfvars   # then edit
export SPACELIFT_API_KEY_ENDPOINT=https://<your-account>.app.spacelift.io
export SPACELIFT_API_KEY_ID=...      # root-admin key
export SPACELIFT_API_KEY_SECRET=...
terraform init && terraform apply
```

## The promotion model

feature branch → PR → **dev** (autodeploy) → merge `dev`→`stage` (gated) → merge `stage`→`main` =
**prod** (gated).

Each environment is a stack tracking its branch; a merge to a branch triggers that env's stack and
nothing else. dev applies unattended for fast iteration; stage and prod pause at the manual-confirm
gate — that confirm *is* the promotion gate.

| env | branch | autodeploy |
|---|---|---|
| dev | `dev` | yes |
| stage | `stage` | no (gated) |
| prod | `main` | no (gated) |

`autodeploy = true` on dev is a deliberate exception to "elevated stacks do not autodeploy":
`app-factory` mints IAM roles, so unattended dev applies are a conscious trade for iteration speed.
`bootstrap/governance` reports autodeploy per elevated stack but does not fail on it, precisely
because this exception is intentional. Set dev to `false` if unattended IAM changes are not acceptable
in your account.

## app-factory is an elevated stack

It runs with a write-enabled AWS integration and mints one least-privilege app role per app, so it
gets the same treatment as the other engines:

| control | value |
|---|---|
| `worker_pool_id` | private `elevated-engines` pool (backlog item 5) |
| `protect_from_deletion` | `true` — destroying it takes a whole env plane with it |
| `enable_well_known_secret_masking` | `true` |
| labels | `env:<env>`, `app-factory`, `elevated` |

The env Spaces keep `inherit_entities = true`, which is what lets them see the root-level AWS
integration, the private worker pool **and** the root-published policy set. That means they need no
entry in `bootstrap/governance`'s `policy_spaces`.

## Add an environment

Add one entry to `environments` in your `terraform.tfvars` — that's the whole procedure:

```hcl
qa = { branch = "qa", autodeploy = false, aws_integration_id = "<qa account's integration ULID>" }
```

The variable has **no default**: integration ULIDs are account-specific, and a stale default pointing
at someone else's AWS account is a real incident. `terraform.tfvars.example` carries the dev/stage/prod
shape.

## One account per env (and why namespacing exists)

"Identical across 3 environments" really means **one AWS account per env** (the landing-zone model).
In a single account, identical engines collide on globally-unique/named resources: S3 bucket names,
the OIDC provider, the IAM boundary policy. So the design is per-env branch + per-env stack + per-env
AWS integration — and where one account is shared anyway, the env is baked into resource names. This
config does both: each env takes its own `aws_integration_id`, and the vended app is named
`demo-<env>` so bucket/secret names differ per env — collision-safe even on a shared demo account.

## Scope

This stands up app-factory per env. The same `env/` module pattern extends to iam-factory /
onboarding-engine — but those own global resources (the OIDC provider, the boundary policy), so they
specifically need per-env accounts or env-suffixed global names.
