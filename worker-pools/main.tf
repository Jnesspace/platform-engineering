# Private worker pool for elevated stacks: docs/hardening-backlog.md item 5.
resource "spacelift_worker_pool" "elevated" {
  name        = "elevated-engines"
  description = "Private pool for stacks that run with elevated role bindings (onboarding engine, iam-factory). Keeps their tokens off shared workers."
  # CSR and worker configuration are supplied out-of-band by the platform admin.
}
