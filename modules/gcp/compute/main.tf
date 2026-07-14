resource "google_compute_instance" "this" {
  name         = var.name
  project      = var.project
  zone         = var.zone
  machine_type = "e2-micro"
  labels       = var.labels

  boot_disk {
    initialize_params {
      image = var.image
    }
  }

  network_interface {
    network = var.network

    access_config {
      # Ephemeral public IP.
    }
  }
}
