output "id" {
  description = "Cloud SQL instance id."
  value       = google_sql_database_instance.this.id
}

output "name" {
  description = "Cloud SQL instance name."
  value       = google_sql_database_instance.this.name
}

output "endpoint" {
  description = "Reachable IP address of the instance: the private IP when private_network is set, otherwise the public IP."
  value       = var.private_network != null ? google_sql_database_instance.this.private_ip_address : google_sql_database_instance.this.public_ip_address
}

output "access" {
  description = "How an app reaches this database: host/port plus the role needed to connect. No credentials here — this module creates no database user."
  value = {
    host            = var.private_network != null ? google_sql_database_instance.this.private_ip_address : google_sql_database_instance.this.public_ip_address
    port            = 5432
    database        = google_sql_database.this.name
    connection_name = google_sql_database_instance.this.connection_name
    role            = "roles/cloudsql.client"
    ssl_mode        = var.ssl_mode
    kms_key_name    = var.kms_key_name
  }
}
