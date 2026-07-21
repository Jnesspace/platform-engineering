# A combination — bucket + database + secret

Composing several modules for one app. Same modules, three ways.

**A. Root config (developer writes it)** — `main.tf` here calls all three modules directly.

**B. Shopping list (GitOps via `patterns/app-factory`)** — one `platform.yaml` vends all three **plus one least-privilege IAM role** covering exactly them:
```yaml
name: acme-billing
cloud: aws
resources:
  object_storage: [{ name: uploads }]
  database:       [{ name: app }]
  secrets:        [{ name: app-secrets }]
```

**C. Blueprint (non-dev / ticket)** — fill [`blueprints/app.yaml`](../../blueprints/app.yaml) (app name, team); it drives `app-factory` with the same modules.

Difference from calling modules directly: **B and C also aggregate each module's `iam_policy_json` into one scoped app role** (see `patterns/app-factory/iam.tf`). Path A leaves IAM to you.
