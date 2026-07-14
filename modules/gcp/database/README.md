# gcp/database

Opinionated Cloud SQL Postgres ("small" tier): POSTGRES_15 on `db-f1-micro`, plus one initial database.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | `string` | (required) | Cloud SQL instance name. |
| `labels` | `map(string)` | `{}` | Applied as `user_labels` on the instance. |
| `project` | `string` | `null` (provider default) | GCP project ID. |
| `region` | `string` | `"us-central1"` | Instance region. |
| `database_name` | `string` | `"app"` | Initial database created on the instance. |
| `deletion_protection` | `bool` | `false` | Protect from terraform destroy. |

## Outputs

| Name | Description |
|------|-------------|
| `id` | Cloud SQL instance id. |
| `name` | Cloud SQL instance name. |
| `endpoint` | Public IP of the instance. |
| `access` | `{ host, port, database, connection_name, role }` — connect data plus `roles/cloudsql.client` for IAM wiring. |

## Use it 3 ways

1. **app-factory shopping list** — add to your app's `platform.yaml`:

   ```yaml
   resources:
     database:
       - name: app
         engine: postgres
   ```

2. **Blueprint (ticketing path)** — a non-developer fills `name` (and optionally `region`) in a Spacelift Blueprint form; the generated stack calls this module.

3. **Standalone**:

   ```hcl
   module "db" {
     source = "git::https://.../platform-engineering//modules/gcp/database"
     name   = "my-app-db"
   }
   ```
