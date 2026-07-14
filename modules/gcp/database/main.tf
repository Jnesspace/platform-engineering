resource "google_sql_database_instance" "this" {
  name             = var.name
  project          = var.project
  region           = var.region
  database_version = "POSTGRES_15"

  deletion_protection = var.deletion_protection

  settings {
    tier        = "db-f1-micro"
    user_labels = var.labels
  }
}

resource "google_sql_database" "this" {
  name     = var.database_name
  project  = var.project
  instance = google_sql_database_instance.this.name
}
