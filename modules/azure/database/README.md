# azure/database

Opinionated small-tier Postgres: one `azurerm_postgresql_flexible_server` (`B_Standard_B1ms`, 32 GB) plus one `azurerm_postgresql_flexible_server_database`. The admin password is generated with `random_password` and surfaced only through the sensitive `access` output.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | — (required) | Logical name; server is named `<name>-pg`. |
| `tags` | `map(string)` | `{}` | Tags applied where supported. |
| `resource_group_name` | `string` | `"app-factory-rg"` | Existing resource group. Override for real deployments. |
| `location` | `string` | `"eastus"` | Azure region. |
| `postgres_version` | `string` | `"15"` | PostgreSQL major version. |
| `admin_username` | `string` | `"appadmin"` | Administrator login. |
| `database_name` | `string` | `"app"` | Database created on the server. |
| `sku_name` | `string` | `"B_Standard_B1ms"` | Server SKU. |
| `storage_mb` | `number` | `32768` | Storage in MB. |

## Outputs

| Name | Description |
|---|---|
| `id` | Flexible server resource id. |
| `name` | Actual server name created. |
| `endpoint` | Server FQDN. |
| `access` | Sensitive. `{ host, port, database, username, password, role, scope }` — connection details plus the RBAC role/scope for an app identity. |

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
