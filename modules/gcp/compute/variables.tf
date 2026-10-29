variable "name" {
  description = "Logical name; used as the instance name."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,61}[a-z0-9])?$", var.name))
    error_message = "name must be 1-63 chars, start with a lowercase letter, contain only lowercase letters, digits and hyphens, and not end with a hyphen (GCE resource naming rules)."
  }
}

variable "labels" {
  description = "Labels applied to the instance."
  type        = map(string)
  default     = {}
}

variable "project" {
  description = "GCP project ID. Defaults to the provider's project."
  type        = string
  default     = null
}

variable "zone" {
  description = "Zone for the instance."
  type        = string
  default     = "us-central1-a"

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+-[a-z]$", var.zone))
    error_message = "zone must look like us-central1-a."
  }
}

variable "machine_type" {
  description = "Machine type. Small shared-core tier by default."
  type        = string
  default     = "e2-micro"
}

variable "image" {
  description = "Boot disk image. Must be a UEFI-enabled image: this module always turns Shielded VM on."
  type        = string
  default     = "debian-cloud/debian-12"
}

variable "boot_disk_size_gb" {
  description = "Boot disk size in GiB."
  type        = number
  default     = 20

  validation {
    condition     = var.boot_disk_size_gb >= 10 && var.boot_disk_size_gb <= 65536
    error_message = "boot_disk_size_gb must be between 10 and 65536."
  }
}

variable "boot_disk_type" {
  description = "Boot disk type."
  type        = string
  default     = "pd-balanced"

  validation {
    condition     = contains(["pd-standard", "pd-balanced", "pd-ssd"], var.boot_disk_type)
    error_message = "boot_disk_type must be pd-standard, pd-balanced or pd-ssd."
  }
}

variable "network" {
  description = "Network to attach the instance to."
  type        = string
  default     = "default"
}

variable "subnetwork" {
  description = "Subnetwork for the NIC. Null lets GCE pick the network's subnet in this region; production should pass a private subnet with Private Google Access."
  type        = string
  default     = null
}

variable "assign_public_ip" {
  description = "Attach an ephemeral external IP. Off by default — a VM with no external IP has no inbound internet path at all. Reach it via IAP TCP forwarding or a bastion."
  type        = bool
  default     = false
}

variable "kms_key_name" {
  description = "Cloud KMS CryptoKey resource name (CMEK) for the boot disk. Null uses Google-managed keys — the disk is encrypted either way. The key must be in the instance region and grant roles/cloudkms.cryptoKeyEncrypterDecrypter to the Compute Engine service agent."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_name == null || can(regex("^projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$", var.kms_key_name))
    error_message = "kms_key_name must be null or a full CryptoKey resource name."
  }
}

variable "service_account_email" {
  description = "Service account to run the instance as. Null attaches none, so the instance holds no Google API credentials — deliberately not the default compute service account, which is over-privileged."
  type        = string
  default     = null

  validation {
    condition     = var.service_account_email == null || can(regex("^[^@]+@[^@]+\\.iam\\.gserviceaccount\\.com$", var.service_account_email))
    error_message = "service_account_email must be null or a service account email (…@….iam.gserviceaccount.com)."
  }
}

variable "service_account_scopes" {
  description = "OAuth scopes for the attached service account. cloud-platform is correct in modern GCP: scopes are a legacy filter and the real limit is the service account's IAM roles."
  type        = list(string)
  default     = ["https://www.googleapis.com/auth/cloud-platform"]
}

variable "metadata" {
  description = "Extra instance metadata. Merged under the module's security keys (enable-oslogin, block-project-ssh-keys, serial-port-enable), which cannot be overridden here. Never put secrets in metadata — anything on the instance can read it."
  type        = map(string)
  default     = {}

  validation {
    condition = length(setintersection(keys(var.metadata), [
      "enable-oslogin", "block-project-ssh-keys", "serial-port-enable", "ssh-keys", "startup-script",
    ])) == 0
    error_message = "metadata must not set enable-oslogin, block-project-ssh-keys, serial-port-enable (module-owned security keys), ssh-keys (use OS Login) or startup-script (a plaintext-secret hazard; bootstrap from Secret Manager instead)."
  }
}

variable "deletion_protection" {
  description = "GCE deletion protection. Off by default: a stateless VM is meant to be replaceable, and on makes terraform destroy fail outright."
  type        = bool
  default     = false
}
