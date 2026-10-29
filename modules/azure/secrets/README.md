# azure/secrets

Opinionated secret storage: one `azurerm_key_vault`, optionally holding one `azurerm_key_vault_secret` (only when `initial_value` is non-empty), with **purge protection on** and a 90-day soft-delete window. Tenant and caller identity come from `data.azurerm_client_config`; the caller gets an access policy so it can manage the secret. The vault name is derived from `name` (lowercased, invalid chars stripped, truncated to 24 chars) and validated against Azure's full naming rules.

## Security posture

| Control | How |
|---|---|
| Encryption at rest | Key Vault encrypts secrets with a Microsoft-managed key by design; `sku_name = "premium"` moves key material into an HSM. There is no CMK knob because Key Vault *is* the key store. |
| Encryption in transit | The Key Vault data plane is HTTPS/TLS-only at the service; there is no plaintext path to deny. |
| No public exposure | Key Vault has no anonymous access path at all. Optional firewall via `network_acls_default_action = "Deny"` with `allowed_ip_rules` / `allowed_subnet_ids` (`0.0.0.0/0` rejected at plan time), plus `public_network_access_enabled`. |
| Durability / recovery | `purge_protection_enabled = true` and `soft_delete_retention_days = 90`, so neither the vault nor the secret can be permanently erased inside the window. |
| Audit logging | Optional diagnostic setting to a Log Analytics workspace, category group `audit` — Key Vault `AuditEvent` records **every secret read**, and without a diagnostic setting they are simply discarded. |
| Least privilege | The only access policy created is for the Terraform caller, and only for `secret_permissions`. The app's grant is `access.role` (`Key Vault Secrets User`) at `access.scope`, bound by the consuming pattern. `enabled_for_deployment` / `enabled_for_disk_encryption` / `enabled_for_template_deployment` are all left off. |
| Secret handling | `initial_value` is a one-time `sensitive` seed: the module sets `lifecycle { ignore_changes = [value] }`, so rotating the secret out-of-band is never reverted by a later apply. The value never appears in `access`, `id` or any other output. |
| Input validation | `name` is checked twice (secret naming rules, plus that it yields ≥3 vault-name characters, mirrored by a `precondition`); SKU, retention, firewall action, bypass, CIDRs, expiry format and diagnostic category are all checked at plan time. |

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | — (required) | Logical name; derives the vault name and names the secret. Validated. |
| `tags` | `map(string)` | `{}` | Tags applied where supported. |
| `resource_group_name` | `string` | `"app-factory-rg"` | Existing resource group. Override for real deployments. |
| `location` | `string` | `"eastus"` | Azure region. |
| `initial_value` | `string` (sensitive) | `""` | One-time seed for the secret; empty creates no secret resource at all. Rotate out-of-band — later changes here are ignored on purpose. |
| `content_type` | `string` | `"text/plain"` | Content type hint on the secret. |
| `expiration_date` | `string` | `null` | RFC 3339 expiry. Null = never expires. |
| `sku_name` | `string` | `"standard"` | `standard` or `premium` (HSM). |
| `purge_protection_enabled` | `bool` | `true` | Block permanent erasure inside the soft-delete window. |
| `soft_delete_retention_days` | `number` | `90` | Recovery window (7–90). |
| `enable_rbac_authorization` | `bool` | `false` | Use Azure RBAC instead of access policies. |
| `caller_secret_permissions` | `list(string)` | `["Get","List","Set","Delete"]` | Caller's access-policy permissions. `Purge` is deliberately absent — it defeats soft-delete; add it only for teardown. |
| `public_network_access_enabled` | `bool` | `true` | Allow public endpoint access. |
| `network_acls_default_action` | `string` | `"Allow"` | `Allow`/`Deny`. |
| `network_acls_bypass` | `string` | `"AzureServices"` | Firewall bypass. |
| `allowed_ip_rules` | `set(string)` | `[]` | Public IPs/CIDRs allowed when Deny. |
| `allowed_subnet_ids` | `set(string)` | `[]` | Subnets allowed when Deny. |
| `log_analytics_workspace_id` | `string` | `null` | Workspace for audit logs. Null = off. |
| `diagnostic_log_category_group` | `string` | `"audit"` | `audit` or `allLogs`. |

## Outputs

| Name | Description |
|---|---|
| `id` | Key vault resource id. |
| `name` | Actual vault name created. |
| `endpoint` | Vault URI. |
| `access` | `{ vault_uri, secret_name, secret_id, role, scope }` — the RBAC role (`Key Vault Secrets User`) and scope to assign to an app identity. |

## Demo vs production

**Read this before your first demo teardown.** `purge_protection_enabled = true` is the production-safe default and it is the most teardown-hostile control in this whole module library:

- Once purge protection is on it **cannot be turned off** on that vault, ever.
- After `terraform destroy`, the vault stays in the soft-deleted state for `soft_delete_retention_days` and **cannot be purged**, so **the vault name is unusable for up to 90 days**. Re-applying the same app name will fail.

For a demo or throwaway stack, set both:

```hcl
purge_protection_enabled   = false
soft_delete_retention_days = 7   # the minimum; a soft-deleted vault can then be purged
```

With purge protection off you can `az keyvault purge --name <vault>` and immediately reuse the name.

Two further defaults are looser than production, both because the Terraform run has to reach the vault **data plane** to write the secret in the same apply that creates the vault:

| Input | Default | Production value | Why |
|---|---|---|---|
| `enable_rbac_authorization` | `false` | `true` | With RBAC on, the run identity needs a `Key Vault Secrets Officer` assignment *before* the secret write. This module will not create role assignments (`policies/plan/deny-privileged-iam.rego` would deny it anyway). |
| `network_acls_default_action` | `"Allow"` | `"Deny"` + your runner CIDRs | Spacelift workers have unpredictable egress IPs unless you run a private worker pool (`worker-pools/`). |

## Deliberately not included

- **No role assignment for the app.** `access.role` + `access.scope` is the binding data; creating the assignment is the consuming pattern's job, and `policies/plan/deny-privileged-iam.rego` exists precisely to keep resource modules out of that business.
- **No `lifecycle { prevent_destroy }`.** It cannot be driven by a variable, so it would hard-block every teardown with no escape hatch. `purge_protection_enabled` gives recoverability without that.
- **No key or certificate objects.** This module's contract is one secret.
- **No private endpoint.** VNet, subnet and private DNS zone belong to the network layer.

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
