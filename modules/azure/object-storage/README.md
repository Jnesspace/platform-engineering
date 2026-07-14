# azure/object-storage

Opinionated small-tier blob storage: one `azurerm_storage_account` (Standard LRS, TLS 1.2 minimum) with one private `azurerm_storage_container`. The storage account name is derived from `name` (lowercased, non-alphanumerics stripped, truncated to 24 chars).

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | — (required) | Logical name; derives the storage account name. |
| `tags` | `map(string)` | `{}` | Tags applied where supported. |
| `resource_group_name` | `string` | `"app-factory-rg"` | Existing resource group. Override for real deployments. |
| `location` | `string` | `"eastus"` | Azure region. |
| `container_name` | `string` | `"data"` | Blob container name. |

## Outputs

| Name | Description |
|---|---|
| `id` | Storage account resource id. |
| `name` | Actual storage account name created. |
| `endpoint` | Primary blob endpoint. |
| `access` | `{ account, container, blob_endpoint, role, scope }` — the RBAC role (`Storage Blob Data Contributor`) and scope to assign to an app identity. |

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
