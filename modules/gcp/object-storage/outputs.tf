output "id" {
  description = "Bucket id."
  value       = google_storage_bucket.this.id
}

output "name" {
  description = "Bucket name."
  value       = google_storage_bucket.this.name
}

output "endpoint" {
  description = "Bucket base URL."
  value       = google_storage_bucket.this.url
}

output "access" {
  description = "How an app reaches this bucket: role/member data for IAM wiring."
  value = {
    bucket   = google_storage_bucket.this.name
    url      = google_storage_bucket.this.url
    role     = "roles/storage.objectAdmin"
    resource = "projects/_/buckets/${google_storage_bucket.this.name}"
  }
}
