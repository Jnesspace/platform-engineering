resource "google_storage_bucket" "this" {
  name          = var.name
  project       = var.project
  location      = var.location
  labels        = var.labels
  force_destroy = var.force_destroy

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }
}
