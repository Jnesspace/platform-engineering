# gcp/object-storage

Opinionated GCS bucket ("small" tier): uniform bucket-level access enforced, versioning on, private by default.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | `string` | (required) | Bucket name (globally unique). |
| `labels` | `map(string)` | `{}` | Labels applied to the bucket. |
| `project` | `string` | `null` (provider default) | GCP project ID. |
| `location` | `string` | `"US"` | Bucket location. |
| `force_destroy` | `bool` | `false` | Allow delete with objects present. |

## Outputs

| Name | Description |
|------|-------------|
| `id` | Bucket id. |
| `name` | Bucket name. |
| `endpoint` | Bucket base URL (`gs://...` style URL). |
| `access` | `{ bucket, url, role, resource }` — role/member data for IAM wiring (`roles/storage.objectAdmin` on this bucket). |

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
