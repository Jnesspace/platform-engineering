resource "google_secret_manager_secret" "this" {
  secret_id = var.name
  project   = var.project
  labels    = var.labels

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "initial" {
  count = var.initial_value != "" ? 1 : 0

  secret      = google_secret_manager_secret.this.id
  secret_data = var.initial_value
}
