output "id" {
  description = "Instance id (self link path)."
  value       = google_compute_instance.this.id
}

output "name" {
  description = "Instance name."
  value       = google_compute_instance.this.name
}

output "endpoint" {
  description = "Internal IP of the instance — the reachable address, since there is no external IP unless assign_public_ip is on."
  value       = google_compute_instance.this.network_interface[0].network_ip
}

output "access" {
  description = "How to reach this instance: IPs/zone plus the role needed to log in. external_ip is empty unless assign_public_ip is on."
  value = {
    external_ip = try(google_compute_instance.this.network_interface[0].access_config[0].nat_ip, "")
    internal_ip = google_compute_instance.this.network_interface[0].network_ip
    zone        = google_compute_instance.this.zone
    role        = "roles/compute.osLogin"
  }
}
