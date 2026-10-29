# Private worker pool for elevated stacks (they mint IAM roles).
resource "spacelift_worker_pool" "elevated" {
  name        = "elevated-engines"
  description = "Private pool for stacks that run with elevated role bindings (app-factory, iam-factory). Keeps their tokens off shared workers."
  # CSR and worker configuration are supplied out-of-band by the platform admin.
}
