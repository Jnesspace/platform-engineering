# Worker pools — private pool for elevated stacks

Reference `spacelift_worker_pool` for [`docs/hardening-backlog.md`](../docs/hardening-backlog.md)
item 5: the elevated engines (onboarding engine, iam-factory) run with
stack-bound admin tokens, and on shared workers any co-tenant run widens the
theft surface. Point elevated stacks at this pool via `worker_pool_id`; the
CSR and worker registration are handled out-of-band by the platform admin.
