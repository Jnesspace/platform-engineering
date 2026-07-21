# bootstrap/environments

Root-admin, one-time: `for_each` over `var.environments` stands up a per-env
platform plane — a `platform-<env>` Space plus an `app-factory-<env>` stack
tracking that env's branch. This is the git-promotion model as code.

## The promotion model

feature branch → PR → **dev** (autodeploy) → merge `dev`→`stage` (gated) →
merge `stage`→`main` = **prod** (gated).

Each environment is a stack tracking its branch; a merge to a branch triggers
that env's stack and nothing else. dev applies unattended for fast iteration;
stage and prod pause at the manual-confirm gate — that confirm *is* the
promotion gate.

| env | branch | autodeploy |
|---|---|---|
| dev | `dev` | yes |
| stage | `stage` | no (gated) |
| prod | `main` | no (gated) |

## Add an environment

Add one entry to `var.environments` — that's the whole procedure:

```hcl
qa = { branch = "qa", autodeploy = false, aws_integration_id = "<qa account's integration>" }
```

## One account per env (and why namespacing exists)

"Identical across 3 environments" really means **one AWS account per env**
(the landing-zone model). In a single account, identical engines collide on
globally-unique/named resources: S3 bucket names, the OIDC provider, the IAM
boundary policy. So the design is per-env branch + per-env stack + per-env
AWS integration — and where one account is shared anyway, the env is baked
into resource names. This config does both: each env takes its own
`aws_integration_id` (all three default to the same demo integration), and
the vended app is named `demo-<env>` so bucket/secret names differ per env —
collision-safe even on the shared demo account.

## Scope

This stands up app-factory per env. The same `env/` module pattern extends to
iam-factory / onboarding-engine — but those own global resources (the OIDC
provider, the boundary policy), so they specifically need per-env accounts or
env-suffixed global names.
