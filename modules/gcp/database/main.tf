# Opinionated Cloud SQL Postgres: SSL-only, zero authorized networks, backups + PITR on, deletion protected. CMEK optional.

resource "google_sql_database_instance" "this" {
  name             = var.name
  project          = var.project
  region           = var.region
  database_version = var.database_version

  # Cloud SQL always encrypts at rest; this only moves key ownership to the caller.
  encryption_key_name = var.kms_key_name

  # Terraform-side guard; the API-side guard is settings.deletion_protection_enabled below.
  deletion_protection = var.deletion_protection

  settings {
    tier              = var.tier
    edition           = var.edition
    availability_type = var.availability_type
    user_labels       = var.labels
    disk_type         = var.disk_type
    disk_autoresize   = true

    deletion_protection_enabled = var.deletion_protection

    ip_configuration {
      # A public IP with zero authorized networks is unreachable from the internet;
      # pass private_network to drop the public IP entirely.
      ipv4_enabled    = var.private_network == null
      private_network = var.private_network
      ssl_mode        = var.ssl_mode

      dynamic "authorized_networks" {
        for_each = var.authorized_networks

        content {
          name  = authorized_networks.value.name
          value = authorized_networks.value.cidr
        }
      }
    }

    # Retention alone is not recoverability: PITR is what lets you land between backups.
    backup_configuration {
      enabled                        = true
      start_time                     = var.backup_start_time
      point_in_time_recovery_enabled = var.point_in_time_recovery_enabled
      transaction_log_retention_days = var.transaction_log_retention_days

      backup_retention_settings {
        retained_backups = var.retained_backups
        retention_unit   = "COUNT"
      }
    }

    dynamic "database_flags" {
      for_each = var.database_flags

      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
  }
}

resource "google_sql_database" "this" {
  name     = var.database_name
  project  = var.project
  instance = google_sql_database_instance.this.name
}
