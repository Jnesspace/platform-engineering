variable "name" {
  description = "Logical name; used as the RDS identifier and to derive the secret name (lowercase, hyphens)."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource this module creates."
  type        = map(string)
  default     = {}
}

variable "engine_version" {
  description = "PostgreSQL major (or major.minor) version."
  type        = string
  default     = "16"
}

variable "instance_class" {
  description = "RDS instance class. Small tier by default."
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage_gb" {
  description = "Allocated storage in GiB."
  type        = number
  default     = 20
}

variable "database_name" {
  description = "Name of the initial database created inside the instance."
  type        = string
  default     = "app"
}

variable "master_username" {
  description = "Master username. Password is generated and stored in Secrets Manager — never an input."
  type        = string
  default     = "app_admin"
}
