# Opinionated small Compute Engine VM: Shielded VM on, no public IP, OS Login enforced, project-wide SSH keys and the serial console blocked, no service account unless asked for. CMEK optional.

locals {
  # Explicit metadata wins where it must, but the security keys are not negotiable through var.metadata.
  metadata = merge(var.metadata, {
    enable-oslogin            = "TRUE"
    block-project-ssh-keys    = "TRUE"
    serial-port-enable        = "FALSE"
    google-logging-enabled    = "true"
    google-monitoring-enabled = "true"
  })
}

resource "google_compute_instance" "this" {
  name         = var.name
  project      = var.project
  zone         = var.zone
  machine_type = var.machine_type
  labels       = var.labels

  can_ip_forward      = false
  deletion_protection = var.deletion_protection
  metadata            = local.metadata

  # Measured boot plus a vTPM: detects rootkits and bootloader tampering.
  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  boot_disk {
    # Persistent disks are always encrypted; this only moves key ownership to the caller.
    kms_key_self_link = var.kms_key_name

    initialize_params {
      image = var.image
      size  = var.boot_disk_size_gb
      type  = var.boot_disk_type
    }
  }

  network_interface {
    network    = var.network
    subnetwork = var.subnetwork

    # No access_config means no external IP at all; reach the VM via IAP or a bastion.
    dynamic "access_config" {
      for_each = var.assign_public_ip ? [1] : []

      content {}
    }
  }

  # Omitted entirely by default: an instance with no service account has no Google API credentials.
  dynamic "service_account" {
    for_each = var.service_account_email == null ? [] : [var.service_account_email]

    content {
      email  = service_account.value
      scopes = var.service_account_scopes
    }
  }
}
