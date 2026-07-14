provider "google" {
  project = "example-project"
  region  = "us-central1"
}

module "compute" {
  source = "../.."

  name = "example-app-vm"
}
