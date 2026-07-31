# Worker pools — private pool for elevated stacks

`spacelift_worker_pool` for [`docs/hardening-backlog.md`](../docs/hardening-backlog.md) item 5: the
elevated stacks (`iam-factory`, the onboarding engine, the per-env `app-factory` stacks) run with
stack-bound admin tokens and cloud credentials. On shared workers any co-tenant run widens the theft
surface, so they run here instead.

## Who runs it, with what, when

Platform admin, **root-admin API key**, **before any `bootstrap/*` root**. Worker pools are
account-level objects.

```sh
export SPACELIFT_API_KEY_ENDPOINT=https://<your-account>.app.spacelift.io
export SPACELIFT_API_KEY_ID=...      # root-admin key
export SPACELIFT_API_KEY_SECRET=...
terraform init && terraform apply
```

## How the bootstrap roots find it

By **name**, not by ULID: every `bootstrap/*` root takes `elevated_worker_pool_name` and resolves it
through `data.spacelift_worker_pools`, with a plan-time check that exactly one pool matches. Nothing
crosses a root boundary except a string, there is no shared backend to configure, and a missing pool
is a loud failure instead of a stack silently landing on public workers.

Rejected alternatives: `terraform_remote_state` (needs a shared backend this repo does not
configure) and a hardcoded `worker_pool_id` variable (an account-specific ULID — exactly what
`bootstrap/` was just cleaned of).

## Reachability — the constraint that bites

Worker pools obey Space entity inheritance. A stack can use a pool only if the pool lives in the
stack's own Space, or in an ancestor Space that the stack's Space inherits from. So:

- A pool in `root` serves every Space with `inherit_entities = true`.
- A Space with `inherit_entities = false` cannot see it and needs **its own** pool: apply this root
  a second time with a different `name` and `space_id`, and point that plane's bootstrap root at it.

`bootstrap/governance` audits this: any stack labelled `elevated` with no `worker_pool_id` fails the
plan.

## Workers

`csr`, `config` and `private_key` are deliberately unmanaged — supplying the CSR here would write
the pool's private key into state. Generate the CSR and register workers out-of-band, per
[Spacelift's worker pool docs](https://docs.spacelift.io/concepts/worker-pools).
