# Just an S3 bucket

The same `modules/aws/object-storage` reached three ways — pick by who's asking.

**A. Root config (developer writes it)** — `main.tf` here:
```hcl
module "bucket" {
  source = "../../modules/aws/object-storage"
  name   = "acme-uploads"
}
```
`terraform apply`, or point a Spacelift stack at this directory.

**B. Shopping list (GitOps via `patterns/app-factory`)** — add to `platform.yaml`:
```yaml
resources:
  object_storage:
    - name: uploads
```

**C. Blueprint (non-dev / ticket)** — fill [`blueprints/object-storage.yaml`](../../blueprints/object-storage.yaml) (bucket name, team).

Same module, same guardrails (versioned, all public access blocked, least-privilege `iam_policy_json`). Only the authorship moves.
