# azure/object-storage

Opinionated private blob storage: one `azurerm_storage_account` (HTTPS-only at TLS 1.2, anonymous access off, blob versioning and soft delete on, double encryption at rest) with one private `azurerm_storage_container`. The storage account name is derived from `name` (lowercased, non-alphanumerics stripped, truncated to 24 chars).

## Security posture

| Control | How |
|---|---|
| Encryption at rest | Azure encrypts every account with Microsoft-managed keys. `infrastructure_encryption_enabled = true` adds a second service-managed layer; `cmk_key_vault_key_id` + `cmk_user_assigned_identity_id` switch the account key to your own Key Vault key. |
| Encryption in transit | `https_traffic_only_enabled = true` and `min_tls_version = "TLS1_2"`, so HTTP and TLS 1.0/1.1 are refused at the service. |
| No public exposure | `allow_nested_items_to_be_public = false` (no anonymous blob/container access, whatever a container is later set to) and `container_access_type = "private"`. Optional firewall via `network_rules_default_action = "Deny"` with `allowed_ip_rules` / `allowed_subnet_ids`; `0.0.0.0/0` is rejected at plan time. |
| Durability / recovery | Blob versioning on; soft delete for blobs **and** containers, 7 days each; `account_replication_type` selectable up to GZRS. |
| Audit logging | Optional blob-service diagnostic setting to a Log Analytics workspace (`log_analytics_workspace_id`), which is the only way data-plane reads/writes/deletes become auditable. |
| Secret handling | The `access` output carries **no account key or SAS token** — only the RBAC role and scope, so the app authenticates as a managed identity. |
| Input validation | The derived account name is length-checked both in `validation` and in a `precondition`; container name, replication type, bypass set, firewall CIDRs, soft-delete windows and diagnostic category are all checked at plan time. |

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | — (required) | Logical name; derives the storage account name. Must yield ≥3 alphanumerics. |
| `tags` | `map(string)` | `{}` | Tags applied where supported. |
| `resource_group_name` | `string` | `"app-factory-rg"` | Existing resource group. Override for real deployments. |
| `location` | `string` | `"eastus"` | Azure region. |
| `container_name` | `string` | `"data"` | Blob container name. |
| `account_replication_type` | `string` | `"LRS"` | `LRS`/`ZRS`/`GRS`/`RAGRS`/`GZRS`/`RAGZRS`. |
| `infrastructure_encryption_enabled` | `bool` | `true` | Second encryption layer. Creation-time only. |
| `shared_access_key_enabled` | `bool` | `false` | Allow account-key auth. See tradeoff below. |
| `public_network_access_enabled` | `bool` | `true` | Allow public endpoint access. See tradeoff below. |
| `network_rules_default_action` | `string` | `"Allow"` | `Allow`/`Deny`. See tradeoff below. |
| `network_rules_bypass` | `set(string)` | `["AzureServices"]` | Firewall bypass. |
| `allowed_ip_rules` | `set(string)` | `[]` | Public IPs/CIDRs allowed when Deny. |
| `allowed_subnet_ids` | `set(string)` | `[]` | Subnets allowed when Deny. |
| `blob_soft_delete_days` | `number` | `7` | Soft-delete retention for blobs. |
| `container_soft_delete_days` | `number` | `7` | Soft-delete retention for containers. |
| `cmk_key_vault_key_id` | `string` | `null` | Key Vault key for account CMK. |
| `cmk_user_assigned_identity_id` | `string` | `null` | Identity used to reach the CMK. Required with the key. |
| `log_analytics_workspace_id` | `string` | `null` | Workspace for blob diagnostics. Null = off. |
| `diagnostic_log_category_group` | `string` | `"allLogs"` | `allLogs` or `audit`. |

## Outputs

| Name | Description |
|---|---|
| `id` | Storage account resource id. |
| `name` | Actual storage account name created. |
| `endpoint` | Primary blob endpoint. |
| `access` | `{ account, container, blob_endpoint, role, scope }` — the RBAC role (`Storage Blob Data Contributor`) and scope to assign to an app identity. |

## Demo vs production

Two defaults here are **not** the strictest possible value, and the reason is the same in both cases: `azurerm_storage_container` is created over the storage **data plane**, so locking the data plane down in the same apply that creates the container deadlocks the module. (`shared_access_key_enabled` used to be a third; it now defaults to the strict value.)

| Input | Default | Production value | Why the default is looser |
|---|---|---|---|
| `shared_access_key_enabled` | `false` | `false` | The strict value is the default: account keys bypass Entra RBAC entirely. With keys off, the provider must be configured `storage_use_azuread = true` and the run identity needs `Storage Blob Data Owner` — set it back to `true` only as a compatibility escape hatch. |
| `public_network_access_enabled` | `true` | `false` | With public access off, container creation requires the Terraform runner to sit behind a private endpoint. |
| `network_rules_default_action` | `"Allow"` | `"Deny"` + your runner CIDRs | Spacelift workers have unpredictable egress IPs unless you run a private worker pool (`worker-pools/`), in which case set `Deny` and list them. |

Everything else — TLS, HTTPS-only, anonymous access, versioning, soft delete, infrastructure encryption — is at the production value by default and safe to leave alone.

## Deliberately not included

- **No SAS token or account key output.** Handing out a key is the opposite of the managed-identity model the `access` contract encodes.
- **No `sas_policy` expiry, no immutability policy.** An immutability policy cannot be relaxed once locked — wrong for a demo repo.
- **No private endpoint.** It needs a VNet, a subnet and a private DNS zone, all of which belong to the network layer, not to a per-app storage module.

## Use it 3 ways

1. **app-factory shopping list** — add to your app's `platform.yaml`:
   ```yaml
   resources:
     object_storage:
       - { name: uploads }
   ```
2. **Blueprint / ticketing** — a non-developer fills `name` (and optionally region/RG) in a Spacelift Blueprint form; the generated stack calls this module.
3. **Standalone**:
   ```hcl
   module "uploads" {
     source = "git::https://example.com/platform-engineering//modules/azure/object-storage"
     name   = "uploads"
   }
   ```
