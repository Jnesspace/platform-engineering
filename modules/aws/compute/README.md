# compute (AWS)

A t3.micro EC2 instance on the latest Amazon Linux 2023, private by default: IMDSv2 required, encrypted gp3 root volume, no public IP, no inbound rules, and no way to pass a secret in through user data.

## Security posture

| Control | How |
|---|---|
| Encryption at rest | `root_block_device.encrypted = true` always; `kms_key_arn` switches the volume to a CMK, otherwise the AWS-managed `aws/ebs` key applies. |
| Encryption in transit | Nothing to enforce at the instance level — this module opens no listener. Egress destinations are an input (`egress_cidr_blocks`) so you can force traffic through a proxy. |
| No public exposure | `associate_public_ip_address = false` by default (default subnets set `map_public_ip_on_launch`, so this has to be stated explicitly). Zero ingress rules by default, and `ingress_rules` **rejects `0.0.0.0/0` and `::/0` at plan time**. |
| Instance metadata | `http_tokens = "required"` (IMDSv2 only) with `http_put_response_hop_limit = 1`, closing the classic SSRF-to-credentials path. |
| No plaintext secrets | This module deliberately exposes **no `user_data` input at all**. Attach a role via `iam_instance_profile` and read secrets from Secrets Manager at boot; `instance_metadata_tags` is on so instances can self-identify without baked-in config. |
| Least privilege | `iam_instance_profile` defaults to `null`, so an instance has no AWS credentials unless you give it some. |
| Input validation | `name`, `instance_type`, `vpc_id`, `subnet_id`, volume size, IMDS hop limit and every ingress rule are checked at plan time. |
| Audit logging | Optional one-minute CloudWatch metrics via `detailed_monitoring`. VPC Flow Logs are the real network audit control and belong to the VPC, not to one instance — see "Deliberately not included". |

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | `string` | — (required) | Instance Name tag; derives the SG name. Validated. |
| `tags` | `map(string)` | `{}` | Tags applied to all resources. |
| `instance_type` | `string` | `"t3.micro"` | EC2 instance type. |
| `vpc_id` | `string` | `null` | VPC for the SG. Null discovers the default VPC. |
| `subnet_id` | `string` | `null` | Subnet to launch into. Null picks the first default subnet. |
| `assign_public_ip` | `bool` | `false` | Attach a public IP. |
| `ingress_rules` | `list(object)` | `[]` | Inbound rules. Internet-wide CIDRs rejected at plan time. |
| `egress_cidr_blocks` | `list(string)` | `["0.0.0.0/0"]` | Allowed egress destinations. |
| `kms_key_arn` | `string` | `""` | CMK for the root volume. Empty = AWS-managed `aws/ebs`. |
| `root_volume_size_gb` | `number` | `20` | Root volume size in GiB. |
| `imds_hop_limit` | `number` | `1` | IMDS PUT response hop limit. |
| `iam_instance_profile` | `string` | `null` | Instance profile to attach. |
| `detailed_monitoring` | `bool` | `false` | One-minute CloudWatch metrics. |
| `disable_api_termination` | `bool` | `false` | EC2 termination protection. |

`ingress_rules` entries are `{ description = optional(string), from_port = number, to_port = number, protocol = optional(string, "tcp"), cidr_blocks = list(string) }`.

## Outputs

| Name | Description |
|------|-------------|
| `id` | EC2 instance ID. |
| `name` | Logical instance name. |
| `endpoint` | Private IP. |
| `access` | `{ instance_id, private_ip, public_ip, security_group_id, subnet_id }`. |
| `iam_policy_json` | `""` — a VM confers no API-level app permissions (kept for interface uniformity). |

`iam_policy_json` stays empty even when `kms_key_arn` is set: EC2 decrypts the root volume through its own service grant on the key, not through the application role. `patterns/app-factory/iam.tf` correspondingly omits compute from its policy merge.

## Demo vs production

- **`disable_api_termination` defaults to `false`**, unlike the storage and database modules' protective defaults. Termination protection makes `terraform destroy` fail outright rather than merely warn, and a stateless VM is meant to be replaceable. Set it `true` for anything holding state on its root volume.
- **`assign_public_ip = false` means a default-VPC instance has no inbound path and no NAT.** For a demo that needs to reach the internet from a default public subnet, set `assign_public_ip = true` and accept that it is publicly addressable (ingress is still closed).
- `egress_cidr_blocks` stays open by default so `dnf` and the AWS APIs work out of the box.

## Deliberately not included

- **No `user_data` input.** Every plaintext-secret-in-user-data incident starts with a module that accepts one; user data is readable by anything that can reach IMDS and is stored unencrypted in the instance description. Bootstrap from the instance profile plus Secrets Manager instead.
- **No VPC Flow Logs.** Flow logs are a VPC/subnet/ENI-level resource needing a log destination and a delivery role. A per-instance module creating them would produce one log group per app; that belongs to the network layer.
- **No SSH key pair and no port 22.** Use SSM Session Manager (attach a profile with `AmazonSSMManagedInstanceCore`) — it needs no inbound rule at all.
- **No EBS default-encryption account setting.** `aws_ebs_encryption_by_default` is account-global; a resource module must not flip account-wide switches.

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
