# gcp/compute

Opinionated small Compute Engine VM: `e2-micro`, Debian 12, **Shielded VM on**, **no external IP**, OS Login enforced, project-wide SSH keys and the serial console blocked, and **no service account attached** unless you name one. CMEK optional.

## Security posture

| Control | How |
|---|---|
| Encryption at rest | Persistent disks are always encrypted; `kms_key_name` moves the boot disk to a CMEK. |
| Encryption in transit | Nothing to enforce at the instance level — this module opens no listener and creates no firewall rule. |
| No public exposure | **No `access_config` block by default**, so the instance has no external IP and no inbound internet path. This is the biggest change from the previous version of this module, which handed out an ephemeral public IP. |
| Boot integrity | `shielded_instance_config` with secure boot, vTPM and integrity monitoring all on. |
| Login / SSH | `enable-oslogin = TRUE` (IAM-controlled SSH with audit logs, no key sprawl) and `block-project-ssh-keys = TRUE`, so a project-wide key cannot back-door this VM. `serial-port-enable = FALSE`. |
| No plaintext secrets | `metadata` **rejects `startup-script` and `ssh-keys` at plan time** — anything running on the instance can read metadata, so it is not a secret channel. Bootstrap from Secret Manager using the attached service account. |
| Least privilege | `service_account_email` defaults to `null`, so the `service_account` block is omitted entirely and the VM gets **no** Google API credentials — notably not the over-privileged default compute service account. |
| Audit logging | `google-logging-enabled` / `google-monitoring-enabled` metadata so the Ops Agent ships logs and metrics when installed. OS Login makes every SSH session an audited IAM event. VPC Flow Logs belong to the subnet — see "Deliberately not included". |
| Input validation | `name` and `zone` against GCE naming rules, `kms_key_name` against the CryptoKey resource-name shape, `service_account_email` against the SA email shape, disk size/type against allowed values, and `metadata` against the forbidden-key list. |

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | `string` | (required) | Instance name. Validated. |
| `labels` | `map(string)` | `{}` | Labels applied to the instance. |
| `project` | `string` | `null` (provider default) | GCP project ID. |
| `zone` | `string` | `"us-central1-a"` | Instance zone. |
| `machine_type` | `string` | `"e2-micro"` | Machine type. |
| `image` | `string` | `"debian-cloud/debian-12"` | Boot disk image. Must be UEFI-enabled. |
| `boot_disk_size_gb` | `number` | `20` | Boot disk size in GiB. |
| `boot_disk_type` | `string` | `"pd-balanced"` | Boot disk type. |
| `network` | `string` | `"default"` | Network to attach to. |
| `subnetwork` | `string` | `null` | Subnetwork for the NIC. |
| `assign_public_ip` | `bool` | `false` | Attach an ephemeral external IP. |
| `kms_key_name` | `string` | `null` | CMEK CryptoKey for the boot disk. |
| `service_account_email` | `string` | `null` | Service account to run as. Null attaches none. |
| `service_account_scopes` | `list(string)` | `["…/auth/cloud-platform"]` | OAuth scopes, used only when an SA is attached. |
| `metadata` | `map(string)` | `{}` | Extra metadata. Security keys are module-owned and rejected here. |
| `deletion_protection` | `bool` | `false` | GCE deletion protection. |

## Outputs

| Name | Description |
|------|-------------|
| `id` | Instance id. |
| `name` | Instance name. |
| `endpoint` | **Internal** IP of the instance (was the ephemeral public IP before hardening). |
| `access` | `{ external_ip, internal_ip, zone, role }` — `roles/compute.osLogin` for IAM wiring. `external_ip` is `""` unless `assign_public_ip` is on. |

The `access` shape is unchanged; `external_ip` is simply empty in the default (private) configuration.

## Demo vs production

- **A default instance has no external IP.** Connect with `gcloud compute ssh <name> --tunnel-through-iap` (needs `roles/iap.tunnelResourceAccessor` and a firewall rule allowing `35.235.240.0/20` on TCP 22 — both outside this module). Package installs need Cloud NAT or Private Google Access. For a throwaway demo, set `assign_public_ip = true`.
- **`deletion_protection` defaults to `false`**, unlike the storage/database/secrets modules' protective defaults: deletion protection makes `terraform destroy` fail outright, and a stateless VM is meant to be replaceable. Set it `true` if the boot disk holds anything you care about.
- **Shielded VM requires a UEFI image.** The default Debian 12 image qualifies; a custom image that does not will fail at apply.

## Deliberately not included

- **No firewall rules.** A `google_compute_firewall` is a network-level resource keyed on target tags; one per app instance is how a project ends up with a hundred overlapping rules and an accidental `0.0.0.0/0`. Ingress belongs to the network layer.
- **No `startup-script` / `metadata_startup_script`.** Metadata is readable by every process on the instance and is stored unencrypted in the instance description — the classic plaintext-secret leak. The `metadata` validation blocks it explicitly.
- **No VPC Flow Logs.** They are a subnet property, not an instance property.
- **No service account creation.** Minting identities is what `patterns/iam-factory` exists to gate; pass an existing `service_account_email`.
- **No Confidential Computing.** `e2-micro` does not support it, and enabling it would force a machine-family change on every consumer.

## Use it 3 ways

1. **app-factory shopping list** — add to your app's `platform.yaml`:

   ```yaml
   resources:
     compute:
       - name: worker
   ```

2. **Blueprint (ticketing path)** — a non-developer fills `name` (and optionally `zone`) in a Spacelift Blueprint form; the generated stack calls this module.

3. **Standalone**:

   ```hcl
   module "vm" {
     source = "git::https://.../platform-engineering//modules/gcp/compute"
     name   = "my-app-vm"
   }
   ```
