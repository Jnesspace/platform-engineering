# gcp/secrets

Opinionated Secret Manager secret: auto replication, optional initial version, a 24h recovery window on destroyed versions. CMEK optional.

## Security posture

| Control | How |
|---|---|
| Encryption at rest | Always on — Google-managed keys by default, CMEK when `kms_key_name` is set. |
| Encryption in transit | The Secret Manager API is HTTPS-only; there is no plaintext path to deny. |
| No public exposure | Secret Manager has no public surface. This module creates **no IAM binding at all**, so a new secret is readable by nobody except project-level administrators; `access.role` tells a caller what to bind. |
| Durability / recovery | `version_destroy_ttl` defaults to `"86400s"`, so a destroyed version is recoverable for 24h. Auto replication keeps the secret available across regions. |
| Secret handling | `initial_value` is `sensitive`; the value never appears in `access`, `id` or any other output. |
| Input validation | `name` is checked against Secret Manager secret-id rules; `kms_key_name` against the full CryptoKey resource-name shape; `version_destroy_ttl` against the seconds-string format. |

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | `string` | (required) | Secret id. Validated. |
| `labels` | `map(string)` | `{}` | Labels applied to the secret. |
| `project` | `string` | `null` (provider default) | GCP project ID. |
| `initial_value` | `string` (sensitive) | `""` | If set, creates the first secret version. |
| `kms_key_name` | `string` | `null` | CMEK CryptoKey resource name. Null = Google-managed keys. |
| `version_destroy_ttl` | `string` | `"86400s"` | Delay before a destroyed version is erased. Null disables. |

## Outputs

| Name | Description |
|------|-------------|
| `id` | Full secret resource id (`projects/.../secrets/...`). |
| `name` | Secret id (short name). |
| `endpoint` | `""` (n/a for secrets). |
| `access` | `{ secret_id, secret_ref, role, kms_key_name }` — `roles/secretmanager.secretAccessor` on this secret for IAM wiring. |

GCP modules do not emit `iam_policy_json`. When `kms_key_name` is set the reading principal also needs `roles/cloudkms.cryptoKeyDecrypter` on that key, which is why the key name is surfaced in `access`.

## Demo vs production

- **`version_destroy_ttl = "86400s"` is the production-safe default and does not block teardown** — deleting the *secret* still removes everything immediately; the TTL only delays erasure of an individually destroyed *version*. Set it to `null` if you want version destruction to be instant.
- **CMEK with auto replication needs a global/multi-region key.** A regional key will be rejected; use `user_managed` replication with per-replica keys if you need regional keys (not exposed by this module — see below).

## Deliberately not included

- **No `user_managed` replication.** It would mean a second, mutually exclusive shape for the CMEK input and a per-replica key list, for a control (data residency) that no consumer of this repo has asked for. Auto replication with a multi-region key covers the CMEK requirement.
- **No `rotation` block.** Secret Manager rotation only publishes a Pub/Sub notification — it does not generate a new value — so it requires a topic plus a subscriber to be worth anything. `schedules/secret-rotation` is this repo's rotation story.
- **No IAM binding.** Granting `secretAccessor` to a principal is the consuming pattern's job (and on AWS it is exactly what `iam_policy_json` feeds); a resource module that silently binds identities is how least privilege quietly dies.

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
