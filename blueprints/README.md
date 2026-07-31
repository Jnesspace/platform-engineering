# Blueprints — the non-dev / ticketing path

**Self-service from a form, same modules underneath.** Each blueprint here is a
click-to-deploy catalog item. A non-developer fills a short form; Spacelift
creates a stack that runs `patterns/app-factory` (the same `modules/aws/*` the
GitOps path composes), with the AWS integration attached and an inline shopping
list built from the form.

| blueprint | deploys | inputs beyond the common set |
|---|---|---|
| [`object-storage.yaml`](object-storage.yaml) | an S3 bucket | — |
| [`database.yaml`](database.yaml) | a Postgres database | — |
| [`secrets.yaml`](secrets.yaml) | a Secrets Manager secret | — |
| [`compute.yaml`](compute.yaml) | an EC2 instance | — |
| [`app.yaml`](app.yaml) | a whole app (bucket + secret + one scoped IAM role) | `trust_mode`, `eks_oidc_provider_arn` |

Common set, every blueprint: `app_name`, `team`, `aws_integration_id`,
`worker_pool_id`, `space_id`, `environment`, `region`.

`environment` offers only `dev` and `stage`. A form-created stack may not claim
the `prod` lane — prod is provisioned through
[`bootstrap/environments/`](../bootstrap/environments) and the promotion
branches, and `policies/plan/protect-env-labels.rego` treats `env:*` as a
privilege claim. `environment` and `team` become the `Environment` and `Owner`
tags that `policies/plan/enforce-required-tags.rego` requires; without them every
run is denied at plan.

Each file is a Blueprint **template body** (`inputs:` + `stack:`); the name and
description live on the published Blueprint entity.

## The form is a privileged entry point

A stack these forms create runs `patterns/app-factory` with a **write** AWS
integration and mints an IAM role. That is elevation, so every template carries
the same posture as the GitOps path:

- **`elevated` label** — `bootstrap/governance`'s audit keys off it and fails
  its own plan if such a stack lacks a private worker pool, lacks deletion
  protection, or sits outside policy reach. A form-created stack cannot quietly
  escape the guardrails.
- **`worker_pool_id` is required** — an elevated token must not run beside
  co-tenant runs (`docs/hardening-backlog.md` item 5). See [`../worker-pools/`](../worker-pools).
- **`protect_from_deletion` + `secret_masking_enabled`** are on.
- **`aws_integration_id` and `worker_pool_id` have no defaults.** They are
  account-specific IDs and do not belong in git. The requester pastes them, or
  the platform team publishes a per-account variant of the catalog.
- **`app_name` is validated in the form** against the same charset app-factory
  enforces at plan time (the intersection of the S3/RDS/Secrets Manager naming
  rules), so a bad name fails on the form rather than mid-apply.
- **`trust_mode`** is `ec2` for the single-resource blueprints, because there is
  no Kubernetes in the form path. `app.yaml` lets the requester pick `irsa` and
  supply the cluster's OIDC provider ARN; app-factory fails the plan if the two
  disagree, rather than minting a role no workload can assume.
- **No teardown escape hatch on the form, deliberately.** Vended resources keep
  production defaults — RDS deletion protection and a final snapshot, a 30-day
  secret recovery window, no `force_destroy` on buckets — so `terraform destroy`
  on a blueprint-created stack will *fail*. That is the correct default: a
  requester filling in a form should not be able to make their own data trivially
  destroyable. To tear one down, an operator sets `TF_VAR_demo_teardown = true`
  on the stack, which is somewhere the requester has no write access.

## Publish them
[`../bootstrap/blueprints/`](../bootstrap/blueprints) publishes this catalog as
live, deployable Spacelift Blueprints (`terraform apply` with a root-admin key).

## The tradeoff (important)
Deploying a blueprint creates a stack that **references the modules and injects
variables** — it does **not** commit generated Terraform back to git. When a
reviewable repo artifact is required (security scan, audit), use the GitOps
shopping-list path (`platform.yaml` → `app-factory`) instead: there the
committed YAML *is* the source of truth. Blueprints suit the no-code tier; the
shopping list suits teams that need the code in git. Same modules either way.
