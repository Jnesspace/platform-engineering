# azure/secrets

Opinionated secret storage: one `azurerm_key_vault` (standard SKU) holding one `azurerm_key_vault_secret`. Tenant and caller identity come from `data.azurerm_client_config`; the caller gets an access policy so it can manage the secret. The vault name is derived from `name` (lowercased, invalid chars stripped, truncated to 24 chars).

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | — (required) | Logical name; derives the vault name and names the secret. |
| `tags` | `map(string)` | `{}` | Tags applied where supported. |
| `resource_group_name` | `string` | `"app-factory-rg"` | Existing resource group. Override for real deployments. |
| `location` | `string` | `"eastus"` | Azure region. |
| `initial_value` | `string` (sensitive) | `"placeholder"` | Initial secret value; rotate out-of-band. |

## Outputs

| Name | Description |
|---|---|
| `id` | Key vault resource id. |
| `name` | Actual vault name created. |
| `endpoint` | Vault URI. |
| `access` | `{ vault_uri, secret_name, secret_id, role, scope }` — the RBAC role (`Key Vault Secrets User`) and scope to assign to an app identity. |

## Use it 3 ways

1. **app-factory shopping list** — add to your app's `platform.yaml`:
   ```yaml
   resources:
     secrets:
       - { name: app-secrets }
   ```
2. **Blueprint / ticketing** — a non-developer fills `name` (and optionally region/RG) in a Spacelift Blueprint form; the generated stack calls this module.
3. **Standalone**:
   ```hcl
   module "app_secrets" {
     source = "git::https://example.com/platform-engineering//modules/azure/secrets"
     name   = "app-secrets"
   }
   ```
