# Blueprints — the non-dev / ticketing path

**Self-service from a form, same modules underneath.** Each blueprint here is a
click-to-deploy catalog item. A non-developer fills a short form; Spacelift
creates a stack that runs `patterns/app-factory` (the same `modules/aws/*` the
GitOps path composes), with the AWS integration attached and an inline shopping
list built from the form.

| blueprint | deploys | inputs |
|---|---|---|
| [`object-storage.yaml`](object-storage.yaml) | an S3 bucket | app_name, team, aws_integration_id, space, region |
| [`database.yaml`](database.yaml) | a Postgres database | app_name, team, aws_integration_id, space, region |
| [`secrets.yaml`](secrets.yaml) | a Secrets Manager secret | app_name, team, aws_integration_id, space, region |
| [`compute.yaml`](compute.yaml) | an EC2 instance | app_name, team, aws_integration_id, space, region |
| [`app.yaml`](app.yaml) | a whole app (bucket + secret + one scoped IAM role) | app_name, team, aws_integration_id, space, region |

Each file is a Blueprint **template body** (`inputs:` + `stack:`); the name and
description live on the published Blueprint entity.

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
