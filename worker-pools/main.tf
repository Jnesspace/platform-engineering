# Private worker pool for elevated stacks: docs/hardening-backlog.md item 5. Elevated stacks find it
# BY NAME (data.spacelift_worker_pools in each bootstrap root), so no ULID crosses a root boundary.
resource "spacelift_worker_pool" "elevated" {
  name        = var.name
  space_id    = var.space_id
  description = "Private pool for stacks that run with elevated role bindings (onboarding engine, iam-factory, app-factory). Keeps their tokens off shared workers."
  labels      = ["governance", "elevated"]

  # csr / config / private_key stay unmanaged on purpose: supplying the CSR here would park the
  # pool's private key in state. Register workers out-of-band (see README).
}
