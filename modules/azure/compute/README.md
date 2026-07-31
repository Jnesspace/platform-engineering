# azure/compute

Opinionated small-tier VM: one `azurerm_linux_virtual_machine` (`Standard_B1s`, Ubuntu 22.04 LTS gen2) with one `azurerm_network_interface`. **Trusted Launch on, no public IP, platform patching, a system-assigned identity, SSH-key-only auth, and no way to pass a secret in through custom data.** No password is generated or attached — `disable_password_authentication = true`, unconditionally.

## Security posture

| Control | How |
|---|---|
| Encryption at rest | Azure managed disks are always encrypted at rest; `disk_encryption_set_id` moves the OS disk to a customer-managed key. `encryption_at_host_enabled` additionally encrypts the temp disk and disk caches on the host. |
| Encryption in transit | Nothing to enforce at the instance level — this module opens no listener and authors no NSG rule. |
| No public exposure | The NIC's `ip_configuration` **never sets `public_ip_address_id`**, so the VM has no public IP by construction rather than by default value. `ip_forwarding_enabled = false` stops the VM being used as a router between subnets. |
| Boot integrity | Trusted Launch: `secure_boot_enabled` and `vtpm_enabled` both on. |
| Authentication | SSH-key-only: `admin_ssh_public_key` is required and `disable_password_authentication = true` always. There is no generated-password fallback — a credential nobody chose is a credential nobody rotates. |
| No plaintext secrets | This module exposes **no `custom_data` / `user_data` input at all**. Custom data is readable by anything running on the instance; use the system-assigned identity plus Key Vault instead. |
| Least privilege | `assign_system_identity = true` gives the VM a credential-free way to reach Azure services; the module creates **no role assignment**, so that identity starts with nothing. `identity_principal_id` is output so the consuming pattern can bind exactly what it needs. |
| Patching | `patch_mode` / `patch_assessment_mode` default to `AutomaticByPlatform`, so Azure applies security patches without anyone remembering to. A `precondition` catches the invalid combination. |
| Audit / diagnostics | Managed `boot_diagnostics` on; `allow_extension_operations` left on so the Azure Monitor Agent can be installed. |
| Input validation | `name`, `subnet_id` (full resource-id shape), `size`, `admin_username` (including Azure's disallowed names), SSH key format, disk type/size and both patch modes are checked at plan time. |

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | — (required) | VM name; NIC is `<name>-nic`. Validated. |
| `tags` | `map(string)` | `{}` | Tags applied where supported. |
| `resource_group_name` | `string` | `"app-factory-rg"` | Existing resource group. Override for real deployments. |
| `location` | `string` | `"eastus"` | Azure region. |
| `subnet_id` | `string` | placeholder id | Subnet for the NIC. The default is a placeholder so the module validates standalone — **override with a real subnet id for any actual deployment**. |
| `size` | `string` | `"Standard_B1s"` | VM size. Must support Trusted Launch unless you disable it. |
| `admin_username` | `string` | `"azureuser"` | Admin login. |
| `admin_ssh_public_key` | `string` | — (required) | OpenSSH public key; the only auth path. |
| `secure_boot_enabled` | `bool` | `true` | Trusted Launch secure boot. |
| `vtpm_enabled` | `bool` | `true` | Trusted Launch vTPM. |
| `encryption_at_host_enabled` | `bool` | `false` | Host-level temp-disk/cache encryption. Needs a subscription feature. |
| `os_disk_storage_account_type` | `string` | `"Standard_LRS"` | OS disk type. |
| `os_disk_size_gb` | `number` | `null` | OS disk size. Null keeps the image size. |
| `disk_encryption_set_id` | `string` | `null` | Customer-managed OS disk encryption. |
| `network_security_group_id` | `string` | `null` | NSG to associate with the NIC. |
| `assign_system_identity` | `bool` | `true` | Give the VM a system-assigned identity. |
| `allow_extension_operations` | `bool` | `true` | Allow VM extensions. |
| `patch_mode` | `string` | `"AutomaticByPlatform"` | Guest patching mode. |
| `patch_assessment_mode` | `string` | `"AutomaticByPlatform"` | Patch assessment mode. |
| `boot_diagnostics_enabled` | `bool` | `true` | Managed boot diagnostics. |

## Outputs

| Name | Description |
|---|---|
| `id` | VM resource id. |
| `name` | Actual VM name created. |
| `endpoint` | Private IP address. |
| `access` | Sensitive. `{ private_ip, admin_username, admin_password, role, scope }` — connection details plus a least-privilege RBAC hint (`Virtual Machine Administrator Login`, not Contributor). `admin_password` is always `""` — no password exists. |
| `identity_principal_id` | Object id of the system-assigned identity, for role assignments made outside this module. `""` when the identity is off. |

## Demo vs production

- **`admin_ssh_public_key` is required.** The examples ship a placeholder key so they plan standalone; generate a real keypair for any actual deployment (`ssh-keygen -t ed25519`).
- **`encryption_at_host_enabled` defaults to `false`** because the `EncryptionAtHost` subscription feature must be registered first (`az feature register --namespace Microsoft.Compute --name EncryptionAtHost`), and apply fails outright if it is not. Turn it on once registered.
- **Trusted Launch is on by default.** If your chosen `size` or region does not support it, apply fails; set `secure_boot_enabled = false` and `vtpm_enabled = false` rather than reaching for a Gen1 image.
- **`patch_mode = "AutomaticByPlatform"` means Azure may reboot the VM on its own schedule.** That is correct for a stateless worker; for something latency-sensitive use `ImageDefault` and patch in your own maintenance window.
- **No deletion protection**, matching `aws/compute` and `gcp/compute`: a stateless VM is meant to be replaceable, so `terraform destroy` works unimpeded.

## Deliberately not included

- **No `custom_data` / `user_data`.** Custom data is readable by every process on the VM; it is not a secret channel. Bootstrap from Key Vault with the system-assigned identity.
- **No public IP resource.** There is no variable to add one — reach the VM through Azure Bastion or a jump host.
- **No NSG rules.** An NSG is a shared, subnet-level object; one per app VM is how a subscription ends up with a hundred overlapping rules and an accidental `Internet -> 22`. Pass an existing `network_security_group_id`.
- **No role assignment for the system-assigned identity.** `identity_principal_id` is output so the consuming pattern binds it; `policies/plan/deny-privileged-iam.rego` exists to keep resource modules out of that business.
- **No password at all.** There is nothing to rotate, leak through an output, or write to Key Vault.

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
