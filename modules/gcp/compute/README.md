# gcp/compute

Opinionated Compute Engine VM ("small" tier): `e2-micro`, Debian 12, default network, ephemeral public IP.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | `string` | (required) | Instance name. |
| `labels` | `map(string)` | `{}` | Labels applied to the instance. |
| `project` | `string` | `null` (provider default) | GCP project ID. |
| `zone` | `string` | `"us-central1-a"` | Instance zone. |
| `image` | `string` | `"debian-cloud/debian-12"` | Boot disk image. |
| `network` | `string` | `"default"` | Network to attach to. |

## Outputs

| Name | Description |
|------|-------------|
| `id` | Instance id. |
| `name` | Instance name. |
| `endpoint` | Ephemeral public IP. |
| `access` | `{ external_ip, internal_ip, zone, role }` — `roles/compute.osLogin` for IAM wiring. |

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
