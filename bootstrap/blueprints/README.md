# bootstrap/blueprints — publish the catalog

Publishes [`../../blueprints/`](../../blueprints) as live Spacelift Blueprints a
user can click **Deploy** on. Applied once with a root-admin key:

```sh
terraform init && terraform apply
```

Each blueprint deploys via `patterns/app-factory` (the same modules the GitOps
path uses), with the AWS integration attached and an inline shopping list built
from the form. Deploying one creates a stack that vends the resources — the
generated code is *not* committed to git (that's the blueprint tradeoff; use the
GitOps shopping-list path when a reviewable repo artifact is required).
