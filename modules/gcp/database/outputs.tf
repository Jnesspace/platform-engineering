output "id" {
  description = "Cloud SQL instance id."
  value       = google_sql_database_instance.this.id
}

output "name" {
  description = "Cloud SQL instance name."
  value       = google_sql_database_instance.this.name
}

output "endpoint" {
  description = "Public IP address of the instance."
  value       = google_sql_database_instance.this.public_ip_address
}

output "access" {
  description = "How an app reaches this database: host/port plus the role needed to connect."
  value = {
    host            = google_sql_database_instance.this.public_ip_address
    port            = 5432
    database        = google_sql_database.this.name
    connection_name = google_sql_database_instance.this.connection_name
    role            = "roles/cloudsql.client"
  }
}
