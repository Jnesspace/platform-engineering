# Opinionated private GCS bucket: uniform bucket-level access, public access prevention enforced, versioned, soft-delete window, lifecycle hygiene. CMEK optional.

resource "google_storage_bucket" "this" {
  name          = var.name
  project       = var.project
  location      = var.location
  storage_class = var.storage_class
  labels        = var.labels
  force_destroy = var.force_destroy

  # UBLA kills per-object ACLs; "enforced" prevention makes allUsers/allAuthenticatedUsers grants impossible even for a project owner.
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  # Recovers objects deleted without a live version to fall back to (the gap versioning leaves).
  soft_delete_policy {
    retention_duration_seconds = var.soft_delete_retention_seconds
  }

  # GCS always encrypts at rest; this only moves key ownership to the caller.
  dynamic "encryption" {
    for_each = var.kms_key_name == null ? [] : [var.kms_key_name]

    content {
      default_kms_key_name = encryption.value
    }
  }

  dynamic "logging" {
    for_each = var.access_log_bucket == null ? [] : [var.access_log_bucket]

    content {
      log_bucket        = logging.value
      log_object_prefix = var.access_log_prefix != null ? var.access_log_prefix : var.name
    }
  }

  # Abandoned multipart uploads are invisible in the object listing but still billed.
  lifecycle_rule {
    action {
      type = "AbortIncompleteMultipartUpload"
    }

    condition {
      age = var.abort_incomplete_multipart_upload_days
    }
  }

  dynamic "lifecycle_rule" {
    for_each = var.noncurrent_version_expiration_days > 0 ? [var.noncurrent_version_expiration_days] : []

    content {
      action {
        type = "Delete"
      }

      condition {
        days_since_noncurrent_time = lifecycle_rule.value
        with_state                 = "ARCHIVED"
      }
    }
  }
}
