# app-factory — the shopping-list engine (rung 4: converged onboarding)

A developer writes **one `platform.yaml`** in their app repo; this engine turns
it into cloud resources by composing the same dual-purpose wrappers under
[`modules/`](../../modules) that Blueprints and standalone roots use. The
developer never touches Terraform, providers, or IAM.

```
platform.yaml  ──►  app-factory  ──►  modules/<cloud>/<primitive> (one call per entry)
                        │
                        └──►  ONE app IAM role + policy (AWS), built from each
                              module's iam_policy_json — access to exactly what
                              was ordered, nothing else
```

## Shopping-list schema (`platform.yaml`)

```yaml
name: jimmy-app          # app name; prefixes every resource name
cloud: aws               # aws | azure | gcp — wins over var.cloud
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

## How cloud choice works

Terraform module sources are static, so the engine declares **all twelve**
module blocks (`modules/{aws,azure,gcp}/{object-storage,database,secrets,compute}`)
and gates each with a conditional `for_each`: the selected cloud's blocks get a
map of the requested entries, the other clouds get `{}` and expand to nothing.
Switching cloud is a one-line data change in `platform.yaml`, not a code
change. All three provider blocks are configured; only AWS is exercised live
today.

## The IAM wiring (AWS)

Every AWS module outputs `iam_policy_json` — a least-privilege policy scoped to
the one resource it created. The engine concatenates those statements
(re-Sid'ed to stay unique), and creates one `aws_iam_role` + `aws_iam_policy`
+ attachment per app. Azure/GCP modules instead expose the needed role/scope
inside their `access` output; binding those is a later rung.

## Outputs

| output | what it is |
|---|---|
| `resource_access` | map `"<primitive>/<name>"` => the module's `access` object (sensitive: Azure db/vm access carries credentials) |
| `resource_ids` | same keys => primary id (ARN / resource id / self link), non-sensitive |
| `app_role_arn` | the aggregated app role (AWS; null elsewhere) |

This is exactly what the later k8s deploy rung consumes: mount
`resource_access` as config, run pods as `app_role_arn`.

## Try it (no apply needed)

```sh
terraform init -backend=false
terraform validate
terraform plan   # requires cloud credentials; do not apply from a laptop
```
