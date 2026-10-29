# gcp/database

Opinionated Cloud SQL Postgres: **plaintext connections refused**, **zero authorized networks**, automated backups and point-in-time recovery on, deletion protected on both the Terraform and API sides. CMEK optional.

## Security posture

| Control | How |
|---|---|
| Encryption at rest | Always on — Google-managed keys by default, CMEK when `kms_key_name` is set. |
| Encryption in transit | `ip_configuration.ssl_mode = "ENCRYPTED_ONLY"`, so the server rejects unencrypted connections. `ALLOW_UNENCRYPTED_AND_ENCRYPTED` is not an accepted value of `ssl_mode` in this module — the `validation` block refuses it. |
| No public exposure | `authorized_networks` defaults to **empty**, so the instance is unreachable from the internet even though it has a public IP; `0.0.0.0/0` is rejected at plan time. Setting `private_network` drops the public IP entirely (`ipv4_enabled = false`). |
| Durability / recovery | `backup_configuration.enabled = true`, `point_in_time_recovery_enabled = true` with 7 days of WAL, 7 retained backups, `disk_autoresize`, and `deletion_protection` set on **both** `google_sql_database_instance.deletion_protection` (Terraform) and `settings.deletion_protection_enabled` (API). |
| Audit logging | `database_flags` default to `log_connections`, `log_disconnections` and `log_statement = ddl` — the audit trail of who connected and what changed shape. |
| Input validation | `name`, `database_version`, `database_name`, `ssl_mode`, `edition`, `availability_type`, `disk_type`, `private_network`, `kms_key_name`, every retention value and every authorized-network CIDR are checked at plan time. |

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | `string` | (required) | Cloud SQL instance name. Validated. |
| `labels` | `map(string)` | `{}` | Applied as `user_labels` on the instance. |
| `project` | `string` | `null` (provider default) | GCP project ID. |
| `region` | `string` | `"us-central1"` | Instance region. |
| `database_version` | `string` | `"POSTGRES_15"` | Cloud SQL PostgreSQL version. |
| `tier` | `string` | `"db-f1-micro"` | Machine tier. |
| `edition` | `string` | `"ENTERPRISE"` | Cloud SQL edition. |
| `availability_type` | `string` | `"ZONAL"` | `ZONAL` / `REGIONAL`. |
| `disk_type` | `string` | `"PD_SSD"` | Data disk type. |
| `database_name` | `string` | `"app"` | Initial database created on the instance. |
| `deletion_protection` | `bool` | `true` | Protect from deletion (Terraform **and** API). |
| `ssl_mode` | `string` | `"ENCRYPTED_ONLY"` | Transport requirement. |
| `private_network` | `string` | `null` | VPC self-link for a private-IP-only instance. |
| `authorized_networks` | `list(object)` | `[]` | Public CIDRs allowed to connect. `0.0.0.0/0` rejected. |
| `kms_key_name` | `string` | `null` | CMEK CryptoKey resource name. |
| `point_in_time_recovery_enabled` | `bool` | `true` | Keep WAL for PITR. |
| `transaction_log_retention_days` | `number` | `7` | Days of WAL retained. |
| `retained_backups` | `number` | `7` | Automated backups retained. |
| `backup_start_time` | `string` | `"03:00"` | Daily UTC backup window start. |
| `database_flags` | `map(string)` | connection + DDL logging | PostgreSQL flags. |

`authorized_networks` entries are `{ name = string, cidr = string }`.

## Outputs

| Name | Description |
|------|-------------|
| `id` | Cloud SQL instance id. |
| `name` | Cloud SQL instance name. |
| `endpoint` | Private IP when `private_network` is set, otherwise the public IP. |
| `access` | `{ host, port, database, connection_name, role, ssl_mode, kms_key_name }` — connect data plus `roles/cloudsql.client` for IAM wiring. |

GCP modules do not emit `iam_policy_json`; `access.role` is the binding data a GCP-side factory would use.

## Demo vs production

- **`deletion_protection` defaults to `true` and flips both guards together.** `terraform destroy` on a protected instance fails; set `deletion_protection = false`, apply that change first, then destroy. This is the single most common demo trip-up on this module.
- **A brand-new instance is reachable by nothing.** With no `authorized_networks` and no `private_network`, you connect through the **Cloud SQL Auth Proxy** or Cloud SQL connectors (which is the right answer in production too — they tunnel over IAM and need no IP allowlist at all). For a quick demo, add your own address: `authorized_networks = [{ name = "my-laptop", cidr = "203.0.113.4/32" }]`.
- For production: set `private_network`, `availability_type = "REGIONAL"`, and pass a `kms_key_name` you control.

## Deliberately not included

- **No database user and no generated password.** Adding a `google_sql_user` would put a live password into the `access` output, which would then have to become `sensitive` — a change that ripples into every root consuming this module. GCP's better answer is IAM database authentication plus the Auth Proxy, and there is no GCP-side secret store wired into this repo yet to hold a password if one were generated. Create users out of band, or wire `modules/gcp/secrets` in.
- **No `pgaudit`.** `cloudsql.enable_pgaudit` also requires the `pgaudit` extension to be created inside each database and `pgaudit.log` flags tuned; a half-configured pgaudit logs nothing while looking like it does. The standard `log_connections` / `log_disconnections` / `log_statement` flags are set instead.
- **No `retention_policy`-style lock.** Nothing on Cloud SQL is irreversible here by design.

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
