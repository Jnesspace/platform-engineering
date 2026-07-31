# gcp/object-storage

Opinionated private GCS bucket: uniform bucket-level access, **public access prevention enforced**, versioning on, a soft-delete window, and lifecycle rules that stop noncurrent versions and abandoned multipart uploads accumulating forever. CMEK optional.

## Security posture

| Control | How |
|---|---|
| Encryption at rest | Always on — Google-managed keys by default, CMEK when `kms_key_name` is set. |
| Encryption in transit | The GCS JSON/XML APIs are HTTPS-only, so there is no plaintext path to deny. See "Deliberately not included". |
| No public exposure | `uniform_bucket_level_access = true` (no per-object ACLs) **and** `public_access_prevention = "enforced"`, which makes an `allUsers` / `allAuthenticatedUsers` binding impossible even for a project owner. |
| Durability / recovery | Object versioning on; `soft_delete_policy` retains deleted objects for 7 days by default; `force_destroy` defaults to `false`; noncurrent versions expire on a schedule you choose. |
| Audit logging | Optional GCS usage/storage logs via `access_log_bucket` / `access_log_prefix`. Data Access audit logs are a project-level setting — see "Deliberately not included". |
| Input validation | `name` is checked against real GCS bucket naming rules (including the `goog` prefix ban), `kms_key_name` against the full CryptoKey resource-name shape, and every retention value is range-checked. |

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | `string` | (required) | Bucket name (globally unique). Validated. |
| `labels` | `map(string)` | `{}` | Labels applied to the bucket. |
| `project` | `string` | `null` (provider default) | GCP project ID. |
| `location` | `string` | `"US"` | Bucket location. |
| `storage_class` | `string` | `"STANDARD"` | Default storage class. |
| `force_destroy` | `bool` | `false` | Allow delete with objects present. |
| `kms_key_name` | `string` | `null` | CMEK CryptoKey resource name. Null = Google-managed keys. |
| `access_log_bucket` | `string` | `null` | Bucket receiving usage/storage logs. Null = off. |
| `access_log_prefix` | `string` | `null` | Log object prefix. Null uses the bucket name. |
| `soft_delete_retention_seconds` | `number` | `604800` | Soft-delete window (0, or 7–90 days in seconds). |
| `noncurrent_version_expiration_days` | `number` | `90` | Expire ARCHIVED versions after N days. `0` disables. |
| `abort_incomplete_multipart_upload_days` | `number` | `7` | Abort incomplete multipart uploads after N days. |

## Outputs

| Name | Description |
|------|-------------|
| `id` | Bucket id. |
| `name` | Bucket name. |
| `endpoint` | Bucket base URL (`gs://...` style URL). |
| `access` | `{ bucket, url, role, resource, kms_key_name }` — role/member data for IAM wiring (`roles/storage.objectAdmin` on this bucket). |

GCP modules do not emit `iam_policy_json`; `access.role` + `access.resource` is the binding data a GCP-side factory would use. When `kms_key_name` is set the app principal additionally needs `roles/cloudkms.cryptoKeyEncrypterDecrypter` on that key, which is why the key name is surfaced in `access`.

## Demo vs production

- **`force_destroy` defaults to `false`**, so `terraform destroy` refuses a non-empty bucket. Set `true` for throwaway demo stacks.
- **`soft_delete_retention_seconds` defaults to 7 days.** Soft-deleted objects are billed for the retention period, and `force_destroy` still works, so this is safe for demos; set `0` if you want deletes to be immediate and free.
- **CMEK setup is a prerequisite, not something this module can do for you**: the key must be in the bucket's location, and the GCS service agent (`service-<project-number>@gs-project-accounts.iam.gserviceaccount.com`) needs `roles/cloudkms.cryptoKeyEncrypterDecrypter` on it *before* the bucket is created.

## Deliberately not included

- **No TLS-deny policy.** Unlike S3, GCS has no `SecureTransport`-equivalent IAM condition because the API accepts no plaintext connections in the first place. There is nothing to enforce.
- **No `retention_policy` / Object Lock.** A locked retention policy cannot be removed, which is the wrong default for a repo used for demos.
- **No project-level Data Access audit log config.** That is an org/project IAM policy change, not a bucket attribute; a resource module must not rewrite project audit config as a side effect.

## Use it 3 ways

1. **app-factory shopping list** — add to your app's `platform.yaml`:

   ```yaml
   resources:
     object_storage:
       - name: uploads
   ```

2. **Blueprint (ticketing path)** — a non-developer fills `name` (and optionally `location`) in a Spacelift Blueprint form; the generated stack calls this module.

3. **Standalone**:

   ```hcl
   module "uploads" {
     source = "git::https://.../platform-engineering//modules/gcp/object-storage"
     name   = "my-app-uploads"
   }
   ```
