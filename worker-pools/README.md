# Worker pools — private pool for elevated stacks

Reference `spacelift_worker_pool` for the app-factory and iam-factory stacks. They run with
write cloud credentials and mint IAM roles, and on shared workers any co-tenant run widens the
theft surface. Point elevated stacks at this pool via `worker_pool_id`; the
CSR and worker registration are handled out-of-band by the platform admin.
