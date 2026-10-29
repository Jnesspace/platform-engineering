# Opinionated Secret Manager secret: value optionally seeded, destroyed versions held for a recovery window. CMEK optional.

resource "google_secret_manager_secret" "this" {
  secret_id = var.name
  project   = var.project
  labels    = var.labels

  # Delayed destruction is the only "undo" Secret Manager offers on a version.
  version_destroy_ttl = var.version_destroy_ttl

  replication {
    auto {
      # Secret Manager always encrypts at rest; this only moves key ownership to the caller.
      dynamic "customer_managed_encryption" {
        for_each = var.kms_key_name == null ? [] : [var.kms_key_name]

        content {
          kms_key_name = customer_managed_encryption.value
        }
      }
    }
  }
}

resource "google_secret_manager_secret_version" "initial" {
  count = var.initial_value != "" ? 1 : 0

  secret      = google_secret_manager_secret.this.id
  secret_data = var.initial_value
}
