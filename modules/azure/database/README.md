# azure/database

Opinionated small-tier Postgres: one `azurerm_postgresql_flexible_server` (`B_Standard_B1ms`, 32 GB) plus one `azurerm_postgresql_flexible_server_database`. **Plaintext connections are refused, no firewall rule exists by default**, backups are retained for 7 days, and connections are logged. With password auth on, the admin password is generated with `random_password` and surfaced only through `sensitive` outputs; in Entra-only mode no password is minted at all.

## Security posture

| Control | How |
|---|---|
| Encryption at rest | Azure encrypts flexible server storage and backups with service-managed keys. `cmk_key_vault_key_id` + `cmk_user_assigned_identity_id` switch it to your own Key Vault key. |
| Encryption in transit | `azurerm_postgresql_flexible_server_configuration` sets `require_secure_transport = on` and `ssl_min_protocol_version = TLSV1.2`. A `validation` block refuses any `server_configurations` override that turns secure transport off. |
| No public exposure | `allowed_cidr_blocks` defaults to **empty**, so zero firewall rules exist and nothing can connect. `0.0.0.0/0` is rejected at plan time (that value is Azure's "allow all Azure services" shortcut and is a common accident). Setting `delegated_subnet_id` sets `public_network_access_enabled = false` and moves the server to a private IP. |
| Durability / recovery | `backup_retention_days` defaults to 7 and is validated to 7–35 — Azure's minimum, so backups cannot be disabled — which is also the point-in-time-restore window. `auto_grow_enabled = true`. Optional `geo_redundant_backup_enabled` and `high_availability_mode`. |
| Audit logging | `log_connections` and `log_disconnections` on. Optional server diagnostic setting to a Log Analytics workspace. |
| Authentication | Optional Entra ID auth (`entra_auth_enabled` + `entra_tenant_id`) so an app can connect as a managed identity with no stored password. An Entra administrator (`entra_admin_object_id`/`entra_admin_principal_name`, plus `azurerm_postgresql_flexible_server_active_directory_administrator`) is required in Entra-only mode — otherwise the password-free server logs nobody in. `precondition`s refuse a configuration where neither auth path is enabled, and a public-endpoint server with zero firewall rules. |
| Secret handling | `access` is `sensitive` (it carries the password), and the password is additionally exposed as the `sensitive` `administrator_password` output for wiring into a secret store. |
| Input validation | `name`, `postgres_version`, `admin_username` (including Azure's reserved names), `database_name`, `sku_name`, `storage_mb`, retention, HA mode, every CIDR **and** every firewall-rule name are checked at plan time; `precondition`s catch the CMK/identity and Entra/tenant pairings. |

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | — (required) | Logical name; server is named `<name>-pg`. Validated. |
| `tags` | `map(string)` | `{}` | Tags applied where supported. |
| `resource_group_name` | `string` | `"app-factory-rg"` | Existing resource group. Override for real deployments. |
| `location` | `string` | `"eastus"` | Azure region. |
| `postgres_version` | `string` | `"15"` | PostgreSQL major version. |
| `admin_username` | `string` | `"appadmin"` | Administrator login. |
| `database_name` | `string` | `"app"` | Database created on the server. |
| `sku_name` | `string` | `"B_Standard_B1ms"` | Server SKU. |
| `storage_mb` | `number` | `32768` | Storage in MB. |
| `server_configurations` | `map(string)` | TLS + connection logging | Server parameters. `require_secure_transport` must stay `on`. |
| `allowed_cidr_blocks` | `list(object)` | `[]` | Public CIDRs allowed, one firewall rule each. `0.0.0.0/0` rejected. |
| `delegated_subnet_id` | `string` | `null` | Delegated subnet for a private-IP server. |
| `private_dns_zone_id` | `string` | `null` | Private DNS zone; required with a delegated subnet. |
| `backup_retention_days` | `number` | `7` | Backup retention / PITR window (7–35). |
| `geo_redundant_backup_enabled` | `bool` | `false` | Replicate backups to the paired region. Creation-time only. |
| `high_availability_mode` | `string` | `null` | `ZoneRedundant` / `SameZone`. Unsupported on `B_` SKUs. |
| `password_auth_enabled` | `bool` | `true` | Allow PostgreSQL password auth. Off = no password is minted. |
| `entra_auth_enabled` | `bool` | `false` | Allow Entra ID auth. |
| `entra_tenant_id` | `string` | `null` | Entra tenant id; required with Entra auth. |
| `entra_admin_object_id` | `string` | `null` | Entra principal to make PG administrator; required in Entra-only mode. |
| `entra_admin_principal_name` | `string` | `null` | Display name of the Entra admin; required with the object id. |
| `entra_admin_principal_type` | `string` | `"Group"` | `User` / `Group` / `ServicePrincipal`. |
| `cmk_key_vault_key_id` | `string` | `null` | Key Vault key for server CMK. |
| `cmk_user_assigned_identity_id` | `string` | `null` | Identity used to reach the CMK. Required with the key. |
| `log_analytics_workspace_id` | `string` | `null` | Workspace for diagnostics. Null = off. |
| `diagnostic_log_category_group` | `string` | `"allLogs"` | `allLogs` or `audit`. |

`allowed_cidr_blocks` entries are `{ name = string, cidr = string }`; `name` becomes the firewall rule name.

## Outputs

| Name | Description |
|---|---|
| `id` | Flexible server resource id. |
| `name` | Actual server name created. |
| `endpoint` | Server FQDN. |
| `access` | Sensitive. `{ host, port, database, username, password, role, scope, sslmode }` — connection details; `password` is null in Entra-only mode, and `role` notes that database auth is not Azure RBAC. |
| `administrator_password` | Sensitive. The generated password on its own, for writing into a secret store. Null in Entra-only mode. |

## Demo vs production

- **A brand-new server is reachable by nothing.** No firewall rule is created. For a demo, add your own address: `allowed_cidr_blocks = [{ name = "my-laptop", cidr = "203.0.113.4/32" }]`. Never use `0.0.0.0/0` — the module rejects it anyway.
- **`geo_redundant_backup_enabled` cannot be changed after creation.** Decide before the first apply; flipping it later replaces the server.
- **Burstable SKUs do not support HA.** Leave `high_availability_mode = null` on `B_Standard_*`, or move to `GP_`/`MO_` first.
- The teardown-hostile knobs live elsewhere in this library — flexible server has no deletion-protection flag, so `terraform destroy` works unimpeded here.

## Deliberately not included

- **The password is not written to Key Vault by this module.** Doing so would couple `azure/database` to `azure/secrets` and pick the vault for you. Take `administrator_password` and feed it to `modules/azure/secrets` (or better, switch to `entra_auth_enabled` and drop the password entirely).
- **No `pgaudit`.** It needs `azure.extensions` to include `PGAUDIT`, the extension created inside each database, and `pgaudit.log` tuned; a half-configured pgaudit logs nothing while appearing to work.
- **No deletion protection.** Flexible server does not expose one; `lifecycle { prevent_destroy }` cannot be driven by a variable, so making it the default would hard-block every teardown with no escape hatch.
- **No private endpoint / VNet.** A delegated subnet and private DNS zone belong to the network layer; pass their ids in.

## Use it 3 ways

1. **app-factory shopping list** — add to your app's `platform.yaml`:
   ```yaml
   resources:
     database:
       - { name: app, engine: postgres }
   ```
2. **Blueprint / ticketing** — a non-developer fills `name` (and optionally region/RG/version) in a Spacelift Blueprint form; the generated stack calls this module.
3. **Standalone**:
   ```hcl
   module "db" {
     source = "git::https://example.com/platform-engineering//modules/azure/database"
     name   = "app"
   }
   ```
