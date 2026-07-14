# compute (AWS)

A t3.micro EC2 instance on the latest Amazon Linux 2023 in the default VPC, behind a minimal security group (no inbound, all outbound).

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | `string` | — (required) | Instance Name tag; derives the SG name. |
| `tags` | `map(string)` | `{}` | Tags applied to all resources. |
| `instance_type` | `string` | `"t3.micro"` | EC2 instance type. |

## Outputs

| Name | Description |
|------|-------------|
| `id` | EC2 instance ID. |
| `name` | Logical instance name. |
| `endpoint` | Private IP. |
| `access` | `{ instance_id, private_ip, public_ip, security_group_id }`. |
| `iam_policy_json` | `""` — a VM confers no API-level app permissions (kept for interface uniformity). |

## Use it 3 ways

1. **app-factory shopping list** — declare it in your app's `platform.yaml`; the engine calls this module:

   ```yaml
   resources:
     compute:
       - name: worker
   ```

2. **Blueprint (ticketing / non-developer path)** — a Spacelift Blueprint exposes `name` as a form field and creates a stack that calls this same module. Same code, filled via a form.

3. **Standalone** — plain Terraform:

   ```hcl
   module "worker" {
     source = "../../modules/aws/compute"
     name   = "my-app-worker"
   }
   ```
