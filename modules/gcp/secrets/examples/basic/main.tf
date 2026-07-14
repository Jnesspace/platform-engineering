provider "google" {
  project = "example-project"
  region  = "us-central1"
}

module "secrets" {
  source = "../.."

  name = "example-app-secrets"
}
