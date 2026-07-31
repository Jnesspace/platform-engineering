# bootstrap/blueprints — publish the catalog

Publishes [`../../blueprints/`](../../blueprints) as live Spacelift Blueprints a user can click
**Deploy** on.

## Who runs it, with what, when

Platform admin, **root-admin API key**, any time after the other bootstrap roots (order does not
matter — this root creates no Spaces, stacks or elevation).

```sh
cp terraform.tfvars.example terraform.tfvars   # then edit, or just accept space = "root"
export SPACELIFT_API_KEY_ENDPOINT=https://<your-account>.app.spacelift.io
export SPACELIFT_API_KEY_ID=...      # root-admin key
export SPACELIFT_API_KEY_SECRET=...
terraform init && terraform apply
```

Each blueprint deploys via `patterns/app-factory` (the same modules the GitOps path uses), with the
AWS integration attached and an inline shopping list built from the form. Deploying one creates a
stack that vends the resources — the generated code is *not* committed to git (that's the blueprint
tradeoff; use the GitOps shopping-list path when a reviewable repo artifact is required).

## Governance gap to know about

Blueprint-created stacks do **not** get `worker_pool_id`, `protect_from_deletion` or an `elevated`
label from this root — those are baked into each `blueprints/*.yaml` template, which lives outside
this directory. Stacks they create land in whichever Space the form picks, so they are only governed
if that Space is reachable from `bootstrap/governance`'s `policy_spaces` (PLAN / GIT_PUSH / APPROVAL /
TRIGGER policies auto-attach with `autoattach:*`, so reachability is the only condition). The
templates also carry a hardcoded `aws_integration_id` form default — fix that in `blueprints/*.yaml`.
