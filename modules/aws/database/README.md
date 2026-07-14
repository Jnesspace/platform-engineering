# database (AWS)

A small, private RDS PostgreSQL instance; the generated master password lives only in Secrets Manager, and apps get a policy to read exactly that secret.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | `string` | — (required) | RDS identifier; also derives the secret name. |
| `tags` | `map(string)` | `{}` | Tags applied to all resources. |
| `engine_version` | `string` | `"16"` | PostgreSQL version. |
| `instance_class` | `string` | `"db.t3.micro"` | Instance class (small tier). |
| `allocated_storage_gb` | `number` | `20` | Storage in GiB. |
| `database_name` | `string` | `"app"` | Initial database name. |
| `master_username` | `string` | `"app_admin"` | Master username (password is generated, never an input). |

## Outputs

| Name | Description |
|------|-------------|
| `id` | DB instance ARN. |
| `name` | RDS identifier created. |
| `endpoint` | `host:port`. |
| `access` | `{ host, port, dbname, username, secret_ref }` — `secret_ref` is the credentials secret ARN. |
| `iam_policy_json` | Least-privilege policy: `secretsmanager:GetSecretValue` on the credentials secret only. |

## Use it 3 ways

1. **app-factory shopping list** — declare it in your app's `platform.yaml`; the engine calls this module and attaches `iam_policy_json` to the app role:

   ```yaml
   resources:
     database:
       - name: app
         engine: postgres
   ```

2. **Blueprint (ticketing / non-developer path)** — a Spacelift Blueprint exposes `name` as a form field and creates a stack that calls this same module. Same code, filled via a form.

3. **Standalone** — plain Terraform:

   ```hcl
   module "db" {
     source = "../../modules/aws/database"
     name   = "my-app-db"
   }
   ```
