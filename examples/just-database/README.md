# Just a Postgres database

The same `modules/aws/database` reached three ways.

**A. Root config (developer writes it)** — `main.tf` here:
```hcl
module "db" {
  source = "../../modules/aws/database"
  name   = "acme-app"
}
```
The master password is generated and stored in Secrets Manager; `module.db.access.secret_ref` is the ARN. Add `rotation_days = 30` to rotate it (pair with [`schedules/secret-rotation`](../../schedules/secret-rotation)).

**B. Shopping list (GitOps via `patterns/app-factory`)** — add to `platform.yaml`:
```yaml
resources:
  database:
    - name: app
```

**C. Blueprint (non-dev / ticket)** — fill [`blueprints/database.yaml`](../../blueprints/database.yaml) (db name, team, instance class).

Same module, same guardrails (private, encrypted, generated password in Secrets Manager). Only the authorship moves.
