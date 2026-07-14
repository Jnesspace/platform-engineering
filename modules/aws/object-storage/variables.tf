variable "name" {
  description = "Logical name; used as the bucket name. Must be globally unique and S3-compatible (lowercase, hyphens)."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource this module creates."
  type        = map(string)
  default     = {}
}

variable "force_destroy" {
  description = "Allow destroying the bucket even when it still holds objects. Keep false outside of throwaway environments."
  type        = bool
  default     = false
}
