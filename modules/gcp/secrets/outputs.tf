output "id" {
  description = "Secret resource id (projects/.../secrets/...)."
  value       = google_secret_manager_secret.this.id
}

output "name" {
  description = "Secret id (short name)."
  value       = google_secret_manager_secret.this.secret_id
}

output "endpoint" {
  description = "Not applicable for secrets."
  value       = ""
}

output "access" {
  description = "How an app reaches this secret: secret ref plus the role needed to read it. References only — the value is never an output."
  value = {
    secret_id  = google_secret_manager_secret.this.secret_id
    secret_ref = google_secret_manager_secret.this.id
    role       = "roles/secretmanager.secretAccessor"
    # A CMEK secret also needs roles/cloudkms.cryptoKeyDecrypter on this key to be readable.
    kms_key_name = var.kms_key_name
  }
}
