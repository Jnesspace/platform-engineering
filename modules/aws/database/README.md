# database (AWS)

A small, private RDS PostgreSQL instance that refuses plaintext connections, keeps automated backups, and never puts its master password in an output. The generated password lives only in Secrets Manager; apps get a policy to read exactly that secret.

## Security posture

| Control | How |
|---|---|
| Encryption at rest | `storage_encrypted = true` always. `kms_key_arn` switches the volume, automated backups, snapshots and the credentials secret to a CMK; otherwise the AWS-managed `aws/rds` and `aws/secretsmanager` keys apply. |
| Encryption in transit | A module-owned parameter group sets `rds.force_ssl = 1`, so the server rejects non-TLS connections. A `validation` block refuses any override that turns it off. |
| No public exposure | `publicly_accessible = false` is hardcoded, not a variable. No ingress rule is created by this module; with no `vpc_security_group_ids` the instance lands on the VPC default SG, which permits no external ingress. |
| Durability / recovery | `backup_retention_days` defaults to 7 and cannot be 0, which is what makes point-in-time restore possible; `copy_tags_to_snapshot`; `delete_automated_backups = false`; `deletion_protection = true`; final snapshot taken on destroy with a collision-safe identifier. |
| Audit logging | `postgresql` and `upgrade` logs exported to CloudWatch Logs; `log_connections` / `log_disconnections` on in the parameter group. Enhanced Monitoring available via `monitoring_role_arn`. |
| Authentication | `iam_database_authentication_enabled = true`, so an app can connect with a short-lived IAM token instead of a stored password. |
| Secret handling | Password generated in-module, written only to Secrets Manager, and never surfaced in `access` or any other output. `secret_recovery_window_days` defaults to 30. |
| Input validation | `name`, `engine_version`, `instance_class`, `database_name`, `master_username` (including reserved-name rejection), storage sizes, windows and retention values are all checked at plan time. |

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | `string` | — (required) | RDS identifier (2–63 chars); also derives the secret and parameter-group names. Validated. |
| `tags` | `map(string)` | `{}` | Tags applied to all resources. |
| `engine_version` | `string` | `"16"` | PostgreSQL version. Major part selects the parameter-group family. |
| `instance_class` | `string` | `"db.t3.micro"` | Instance class (small tier). |
| `allocated_storage_gb` | `number` | `20` | Storage in GiB. |
| `storage_type` | `string` | `"gp3"` | `gp2`/`gp3`/`io1`/`io2`. |
| `database_name` | `string` | `"app"` | Initial database name. |
| `master_username` | `string` | `"app_admin"` | Master username (password is generated, never an input). |
| `rotation_days` | `number` | `0` | When > 0, regenerate the master password on the first apply after every N days; `0` = off. |
| `kms_key_arn` | `string` | `""` | CMK for storage, backups and the credentials secret. Empty = AWS-managed keys. |
| `db_parameters` | `map(string)` | TLS + connection logging | Parameter-group entries. `rds.force_ssl` must stay `"1"`. |
| `backup_retention_days` | `number` | `7` | Automated backup retention (1–35). Enables PITR. |
| `backup_window` | `string` | `null` | `hh:mm-hh:mm` UTC. |
| `maintenance_window` | `string` | `null` | `ddd:hh:mm-ddd:hh:mm` UTC. |
| `delete_automated_backups` | `bool` | `false` | Keep retained backups after the instance is destroyed. |
| `deletion_protection` | `bool` | `true` | Refuse to delete the instance. |
| `skip_final_snapshot` | `bool` | `false` | Skip the final snapshot on destroy. |
| `iam_database_authentication_enabled` | `bool` | `true` | Allow IAM-token auth. |
| `multi_az` | `bool` | `false` | Synchronous standby in a second AZ. |
| `apply_immediately` | `bool` | `false` | Apply modifications outside the maintenance window. |
| `cloudwatch_logs_exports` | `list(string)` | `["postgresql","upgrade"]` | Log types shipped to CloudWatch Logs. |
| `monitoring_role_arn` | `string` | `null` | Enhanced Monitoring role. Null disables it. |
| `monitoring_interval` | `number` | `60` | Enhanced Monitoring granularity, used only with the role. |
| `performance_insights_enabled` | `bool` | `false` | Performance Insights (unsupported on the default class). |
| `performance_insights_retention_days` | `number` | `7` | PI retention. |
| `secret_recovery_window_days` | `number` | `30` | Secrets Manager recovery window for the credentials secret. |
| `db_subnet_group_name` | `string` | `null` | Existing DB subnet group. Pass a private-subnet group in production. |
| `vpc_security_group_ids` | `list(string)` | `[]` | Security groups to attach. |

Rotation only takes effect on an apply after the window elapses — pair with `schedules/secret-rotation` to fire it on a cron.

## Outputs

| Name | Description |
|------|-------------|
| `id` | DB instance ARN. |
| `name` | RDS identifier created. |
| `endpoint` | `host:port`. |
| `access` | `{ host, port, dbname, username, secret_ref, sslmode, kms_key_arn }` — `secret_ref` is the credentials secret ARN. |
| `iam_policy_json` | Least-privilege policy: `secretsmanager:GetSecretValue` on the credentials secret, plus `kms:Decrypt`/`DescribeKey` on the CMK when one is set. |

## Demo vs production

Every teardown-hostile control defaults to the production-safe value. For a demo stack you want:

```hcl
deletion_protection         = false
skip_final_snapshot         = true
secret_recovery_window_days = 0  # otherwise the secret name is blocked for 7-30 days
delete_automated_backups    = true
```

Leaving `secret_recovery_window_days` at `30` and then re-applying the same app name is the most common demo trip-up: Secrets Manager keeps the deleted name reserved, and creation fails with `InvalidRequestException`.

For production, additionally set `multi_az = true`, pass a private `db_subnet_group_name`, and pass a `kms_key_arn` you control.

## Deliberately not included

- **No security group is created.** A module-owned SG would need a VPC lookup and an ingress CIDR list; getting that wrong is how `0.0.0.0/0` ends up on a database. Attach your own via `vpc_security_group_ids`.
- **Performance Insights is off by default** — `db.t3.micro` and `db.t3.small` do not support it, so defaulting it on would fail at apply for the default instance class.
- **Enhanced Monitoring needs a role this module will not mint.** Creating IAM roles inside a resource module is exactly what `patterns/iam-factory` exists to gate.
- **No `manage_master_user_password`.** RDS-managed secrets rotate on their own, but they replace this module's `secret_ref` contract and its `iam_policy_json` scoping.

## Use it 3 ways

1. **app-factory shopping list** — declare it in your app's `platform.yaml`; the engine calls this module and attaches `iam_policy_json` to the app role:

   ```yaml
   resources:
     database:
       - name: app
         engine: postgres
   ```

2. **Blueprint (ticketing / non-developer path)** — a Spacelift Blueprint exposes `name` as a form field and creates a stack that calls this same module. Same code, filled via a form.

3. **Standalone** — plain Terraform:

   ```hcl
   module "db" {
     source = "../../modules/aws/database"
     name   = "my-app-db"
   }
   ```
