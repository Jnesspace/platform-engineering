provider "google" {
  project = "example-project"
  region  = "us-central1"
}

module "database" {
  source = "../.."

  name = "example-app-db"
}
