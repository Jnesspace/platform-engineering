# object-storage (AWS)

A private, versioned S3 bucket with all public access blocked, plus a least-privilege IAM policy for app access.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | `string` | — (required) | Bucket name (globally unique, S3-compatible). |
| `tags` | `map(string)` | `{}` | Tags applied to all resources. |
| `force_destroy` | `bool` | `false` | Allow destroy with objects still present. |

## Outputs

| Name | Description |
|------|-------------|
| `id` | Bucket ARN. |
| `name` | Bucket name created. |
| `endpoint` | Regional bucket domain name. |
| `access` | `{ bucket, arn, regional_domain }`. |
| `iam_policy_json` | Least-privilege policy (list bucket + object Get/Put/Delete) scoped to this bucket. |

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
