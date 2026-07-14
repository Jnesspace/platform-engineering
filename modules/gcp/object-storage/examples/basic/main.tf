provider "google" {
  project = "example-project"
  region  = "us-central1"
}

module "object_storage" {
  source = "../.."

  name = "example-app-uploads"
}
