# secrets (AWS)

A Secrets Manager secret (optionally seeded with an initial value), plus a read-only least-privilege policy for app access.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | `string` | — (required) | Secret name. |
| `tags` | `map(string)` | `{}` | Tags applied to all resources. |
| `initial_value` | `string` (sensitive) | `""` | Optional first version; when empty, set the value out-of-band. |
| `rotation_days` | `number` | `0` | When > 0, generate the value in-module and rotate it every N days (replaces `initial_value`); `0` = off. |

Rotation only takes effect on an apply after the window elapses — pair with `schedules/secret-rotation` to fire it on a cron.

## Outputs

| Name | Description |
|------|-------------|
| `id` | Secret ARN. |
| `name` | Secret name created. |
| `endpoint` | `""` (n/a for secrets). |
| `access` | `{ secret_ref, name }`. |
| `iam_policy_json` | Least-privilege policy: `GetSecretValue` + `DescribeSecret` on this secret only. |

## Use it 3 ways

1. **app-factory shopping list** — declare it in your app's `platform.yaml`; the engine calls this module and attaches `iam_policy_json` to the app role:

   ```yaml
   resources:
     secrets:
       - name: app-secrets
   ```

2. **Blueprint (ticketing / non-developer path)** — a Spacelift Blueprint exposes `name` (and optionally `initial_value`) as form fields and creates a stack that calls this same module. Same code, filled via a form.

3. **Standalone** — plain Terraform:

   ```hcl
   module "app_secrets" {
     source = "../../modules/aws/secrets"
     name   = "my-app-secrets"
   }
   ```
