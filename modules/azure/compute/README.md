# azure/compute

Opinionated small-tier VM: one `azurerm_linux_virtual_machine` (`Standard_B1s`, Ubuntu 22.04 LTS, Standard LRS os disk) with one `azurerm_network_interface`. The admin password is generated with `random_password` and surfaced only through the sensitive `access` output.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | — (required) | VM name; NIC is `<name>-nic`. |
| `tags` | `map(string)` | `{}` | Tags applied where supported. |
| `resource_group_name` | `string` | `"app-factory-rg"` | Existing resource group. Override for real deployments. |
| `location` | `string` | `"eastus"` | Azure region. |
| `subnet_id` | `string` | placeholder id | Subnet for the NIC. The default is a placeholder so the module validates standalone — **override with a real subnet id for any actual deployment**. |
| `size` | `string` | `"Standard_B1s"` | VM size. |
| `admin_username` | `string` | `"azureuser"` | Admin login. |

## Outputs

| Name | Description |
|---|---|
| `id` | VM resource id. |
| `name` | Actual VM name created. |
| `endpoint` | Private IP address. |
| `access` | Sensitive. `{ private_ip, admin_username, admin_password, role, scope }` — connection credentials plus the RBAC role/scope for an app identity. |

## Use it 3 ways

1. **app-factory shopping list** — add to your app's `platform.yaml`:
   ```yaml
   resources:
     compute:
       - { name: worker }
   ```
2. **Blueprint / ticketing** — a non-developer fills `name` and `subnet_id` (and optionally region/RG/size) in a Spacelift Blueprint form; the generated stack calls this module.
3. **Standalone**:
   ```hcl
   module "worker" {
     source    = "git::https://example.com/platform-engineering//modules/azure/compute"
     name      = "worker"
     subnet_id = azurerm_subnet.app.id
   }
   ```
