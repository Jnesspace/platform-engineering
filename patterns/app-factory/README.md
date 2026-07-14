# app-factory — the shopping-list engine (rung 4: converged onboarding)

A developer writes **one `platform.yaml`** in their app repo; this engine turns
it into cloud resources by composing the same dual-purpose wrappers under
[`modules/`](../../modules) that Blueprints and standalone roots use. The
developer never touches Terraform, providers, or IAM.

```
platform.yaml  ──►  app-factory (AWS)  ──►  modules/aws/<primitive> (one call per entry)
                        │
                        └──►  ONE app IAM role + policy (AWS), built from each
                              module's iam_policy_json — access to exactly what
                              was ordered, nothing else
```

## Shopping-list schema (`platform.yaml`)

```yaml
name: jimmy-app          # app name; prefixes every resource name
cloud: aws               # this engine serves aws (azure/gcp: see below)
resources:               # every key optional; entries are lists
  object_storage:
    - name: uploads
  secrets:
    - name: app-secrets
  database:
    - name: app
      engine: postgres   # informational; the module is postgres-only
  compute:
    - name: worker
```

The engine reads it via `var.shopping_list_file` (default:
`../../examples/jimmy-app/platform.yaml`).

## Cloud coverage

This engine is the **AWS path** — the cloud wired live. It composes the
`modules/aws/*` wrappers. Azure and GCP expose the **same module interface**
(`modules/{azure,gcp}/*`, validated), so an Azure or GCP engine is this exact
file with its provider block and `modules/<cloud>/*` swapped in.

Why one root per cloud, not one root for all three? Terraform eagerly configures
**every** declared provider, so a single root declaring aws + azurerm + google
would demand all three clouds' credentials on every run — even an AWS-only one.
Per-cloud engines keep each run to one credential set. The shopping list's
`cloud:` must be `aws` here; anything else fails fast with a pointer to that
cloud's modules.

## The IAM wiring (AWS)

Every AWS module outputs `iam_policy_json` — a least-privilege policy scoped to
the one resource it created. The engine concatenates those statements
(re-Sid'ed to stay unique), and creates one `aws_iam_role` + `aws_iam_policy`
+ attachment per app. Azure/GCP modules instead expose the needed role/scope
inside their `access` output; binding those is a later rung.

## Outputs

| output | what it is |
|---|---|
| `resource_access` | map `"<primitive>/<name>"` => the module's `access` object (marked sensitive as a precaution) |
| `resource_ids` | same keys => primary id (ARN / resource id), non-sensitive |
| `app_role_arn` | the aggregated app IAM role |

This is exactly what the later k8s deploy rung consumes: mount
`resource_access` as config, run pods as `app_role_arn`.

## Try it (no apply needed)

```sh
terraform init -backend=false
terraform validate
terraform plan   # requires cloud credentials; do not apply from a laptop
```
