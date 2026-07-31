# secrets (AWS)

A Secrets Manager secret (optionally seeded with an initial value), encrypted, TLS-only, with a recovery window, plus a read-only least-privilege policy for app access.

## Security posture

| Control | How |
|---|---|
| Encryption at rest | Always encrypted: the AWS-managed `aws/secretsmanager` key by default, a CMK when `kms_key_arn` is set. |
| Encryption in transit | A resource policy `Deny`s `secretsmanager:*` on this secret when `aws:SecureTransport` is false (`enforce_tls_resource_policy`). |
| No public exposure | Secrets Manager has no public surface; access is identity-policy only, and the resource policy grants nothing — it only denies. |
| Durability / recovery | `recovery_window_in_days` defaults to 30, so a deleted secret is recoverable. |
| Secret handling | `initial_value` is `sensitive`; the value never appears in `access`, `id` or any other output. When rotation is on, the value is generated in-module and only ever written to Secrets Manager. |
| Least privilege | `iam_policy_json` is scoped to this secret's ARN and, when a CMK is set, to that key ARN. |
| Input validation | `name` is checked against Secrets Manager naming rules; rotation window, generated length and recovery window are range-checked at plan time. |

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | `string` | — (required) | Secret name. Validated. |
| `tags` | `map(string)` | `{}` | Tags applied to all resources. |
| `initial_value` | `string` (sensitive) | `""` | Optional first version; when empty, set the value out-of-band. |
| `rotation_days` | `number` | `0` | When > 0, generate the value in-module and rotate it every N days (replaces `initial_value`); `0` = off. |
| `generated_value_length` | `number` | `32` | Length of the generated value when rotation is on. |
| `kms_key_arn` | `string` | `""` | CMK encrypting the secret. Empty = AWS-managed key. |
| `recovery_window_in_days` | `number` | `30` | Recovery window before permanent deletion. `0` = delete immediately. |
| `enforce_tls_resource_policy` | `bool` | `true` | Attach the non-TLS deny resource policy. |

Rotation only takes effect on an apply after the window elapses — pair with `schedules/secret-rotation` to fire it on a cron.

## Outputs

| Name | Description |
|------|-------------|
| `id` | Secret ARN. |
| `name` | Secret name created. |
| `endpoint` | `""` (n/a for secrets). |
| `access` | `{ secret_ref, name, kms_key_arn }`. |
| `iam_policy_json` | Least-privilege policy: `GetSecretValue` + `DescribeSecret` on this secret only, plus `kms:Decrypt`/`DescribeKey` on the CMK when one is set. |

## Demo vs production

- **`recovery_window_in_days` defaults to `30`**, the production-safe value. That reserves the secret *name* for the whole window, so re-applying a demo stack with the same app name fails with `InvalidRequestException: You can't create this secret because a secret with this name is already scheduled for deletion`. For demo stacks set `recovery_window_in_days = 0`.
- **A CMK is opt-in.** When you set one, `iam_policy_json` automatically grows the matching `kms:Decrypt` statement — omit that and the app's `GetSecretValue` calls fail at runtime with `AccessDeniedException` on the key, not on the secret, which is a miserable thing to debug in production.

## Deliberately not included

- **No native Secrets Manager rotation (`aws_secretsmanager_secret_rotation`).** It needs a rotation Lambda and its execution role; minting roles inside a resource module is what `patterns/iam-factory` exists to gate. The `time_rotating` mechanism here is the repo's Terraform-native alternative.
- **No `block_public_policy` on the resource policy** — the policy this module attaches contains only a `Deny`, so there is nothing public to block.

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
