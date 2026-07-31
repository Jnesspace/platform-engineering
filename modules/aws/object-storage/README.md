# object-storage (AWS)

A private, versioned, encrypted S3 bucket: all public access blocked, ACLs disabled, non-TLS and sub-TLS1.2 requests denied by bucket policy, lifecycle hygiene on noncurrent versions and abandoned multipart uploads. `iam_policy_json` grants an app access to this bucket (and its CMK) and nothing else.

## Security posture

| Control | How |
|---|---|
| Encryption at rest | Bucket default encryption always on: SSE-S3 (`AES256`) by default, SSE-KMS with S3 Bucket Keys when `kms_key_arn` is set. |
| Encryption in transit | Bucket policy `Deny`s `s3:*` when `aws:SecureTransport` is false, and when `s3:TlsVersion < 1.2`. |
| No public exposure | `aws_s3_bucket_public_access_block` all four flags true; `object_ownership = BucketOwnerEnforced` disables ACLs so identity policy is the only access path. |
| Durability / recovery | Versioning enabled; noncurrent versions expire on a schedule you choose; `force_destroy` defaults to `false`. |
| Audit logging | Optional S3 server access logging via `access_log_bucket` / `access_log_prefix`. |
| Least privilege | `iam_policy_json` is scoped to this bucket ARN and, when a CMK is set, to that key ARN only. |
| Input validation | `name` is checked against real S3 bucket naming rules at plan time; `kms_key_arn` must be a KMS ARN. |

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | `string` | — (required) | Bucket name (globally unique, S3-compatible). Validated against S3 naming rules. |
| `tags` | `map(string)` | `{}` | Tags applied to all resources. |
| `force_destroy` | `bool` | `false` | Allow destroy with objects still present. |
| `kms_key_arn` | `string` | `""` | CMK ARN for SSE-KMS. Empty = SSE-S3 (AWS-managed key). |
| `access_log_bucket` | `string` | `""` | Target bucket for S3 server access logs. Empty = logging off. |
| `access_log_prefix` | `string` | `""` | Log key prefix. Empty derives `s3-access-logs/<name>/`. |
| `noncurrent_version_expiration_days` | `number` | `90` | Expire noncurrent versions after N days. `0` disables the rule. |
| `abort_incomplete_multipart_upload_days` | `number` | `7` | Abort incomplete multipart uploads after N days. |

## Outputs

| Name | Description |
|------|-------------|
| `id` | Bucket ARN. |
| `name` | Bucket name created. |
| `endpoint` | Regional bucket domain name. |
| `access` | `{ bucket, arn, regional_domain, kms_key_arn }`. |
| `iam_policy_json` | Least-privilege policy (list bucket + object Get/Put/Delete) scoped to this bucket, plus `kms:Decrypt`/`GenerateDataKey`/`DescribeKey` on the CMK when one is set. |

## Demo vs production

- **`force_destroy`** defaults to the production-safe `false`, so `terraform destroy` refuses to delete a non-empty bucket. For throwaway demo stacks set `force_destroy = true`.
- **Access logging is off by default** because a bucket cannot log to itself and this module will not create a second bucket behind your back. Point `access_log_bucket` at a central log bucket; that bucket needs a policy allowing `logging.s3.amazonaws.com` to `s3:PutObject` (required, because `BucketOwnerEnforced` means the legacy log-delivery ACL no longer works).
- **CMK is opt-in.** Encryption at rest is never off — the choice is only who owns the key. Pass `kms_key_arn` for key rotation/revocation control and audit trails in CloudTrail.

## Deliberately not included

- No `Deny` statement on unencrypted `PutObject`: bucket default encryption already encrypts every object, and the usual `s3:x-amz-server-side-encryption` deny breaks ordinary uploads that omit the header.
- No Object Lock / retention policy: it cannot be turned off after creation, which is the wrong trade for a repo used for demos.

## Use it 3 ways

1. **app-factory shopping list** — declare it in your app's `platform.yaml`; the engine calls this module and attaches `iam_policy_json` to the app role:

   ```yaml
   resources:
     object_storage:
       - name: uploads
   ```

2. **Blueprint (ticketing / non-developer path)** — a Spacelift Blueprint exposes `name` as a form field and creates a stack that calls this same module. Same code, filled via a form.

3. **Standalone** — plain Terraform:

   ```hcl
   module "uploads" {
     source = "../../modules/aws/object-storage"
     name   = "my-app-uploads"
   }
   ```
