variable "app_name" {
  description = "App name; names the workload objects and the default namespace."
  type        = string
}

variable "image" {
  description = "Container image to run (the app repo's Dockerfile, built and pushed)."
  type        = string
}

variable "app_role_arn" {
  description = "app-factory's `app_role_arn` output — the role the pod assumes via IRSA."
  type        = string
}

variable "bucket" {
  description = "Bucket name, from app-factory's `resource_access[\"object_storage/<name>\"].bucket`."
  type        = string
}

variable "secret_arn" {
  description = "Secret ARN, from app-factory's `resource_access[\"secrets/<name>\"].secret_ref`."
  type        = string
}

variable "region" {
  description = "AWS region the vended resources live in; injected as AWS_REGION."
  type        = string
  default     = "us-east-1"
}

variable "namespace" {
  description = "Namespace for the app. Empty means: use `app_name`."
  type        = string
  default     = ""
}

variable "replicas" {
  description = "Deployment replica count."
  type        = number
  default     = 2
}

variable "container_port" {
  description = "Port the container listens on; the ClusterIP Service exposes it."
  type        = number
  default     = 8080
}
