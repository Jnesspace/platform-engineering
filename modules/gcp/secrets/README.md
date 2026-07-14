# gcp/secrets

Opinionated Secret Manager secret ("small" tier): auto replication, optional initial version.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | `string` | (required) | Secret id. |
| `labels` | `map(string)` | `{}` | Labels applied to the secret. |
| `project` | `string` | `null` (provider default) | GCP project ID. |
| `initial_value` | `string` (sensitive) | `""` | If set, creates the first secret version. |

## Outputs

| Name | Description |
|------|-------------|
| `id` | Full secret resource id (`projects/.../secrets/...`). |
| `name` | Secret id (short name). |
| `endpoint` | `""` (n/a for secrets). |
| `access` | `{ secret_id, secret_ref, role }` — `roles/secretmanager.secretAccessor` on this secret for IAM wiring. |

## Use it 3 ways

1. **app-factory shopping list** — add to your app's `platform.yaml`:

   ```yaml
   resources:
     secrets:
       - name: app-secrets
   ```

2. **Blueprint (ticketing path)** — a non-developer fills `name` in a Spacelift Blueprint form; the generated stack calls this module.

3. **Standalone**:

   ```hcl
   module "app_secrets" {
     source = "git::https://.../platform-engineering//modules/gcp/secrets"
     name   = "my-app-secrets"
   }
   ```
