variable "name" {
  description = "Logical name for this VM. Used for the VM and NIC names."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$", var.name)) && !endswith(var.name, "-")
    error_message = "name must be 1-63 chars, start alphanumeric, contain only letters, digits and hyphens, and not end with a hyphen (Azure VM naming rules; Linux computer names cap at 64)."
  }
}

variable "tags" {
  description = "Tags applied to all resources that support them."
  type        = map(string)
  default     = {}
}

variable "resource_group_name" {
  description = "Resource group to create the VM in. Must already exist."
  type        = string
  default     = "app-factory-rg"
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "eastus"
}

variable "subnet_id" {
  description = "Subnet the NIC attaches to. The default is a placeholder id so the module validates standalone — override it with a real subnet id for any actual deployment."
  type        = string
  default     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/app-factory-rg/providers/Microsoft.Network/virtualNetworks/app-factory-vnet/subnets/default"

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.subnet_id))
    error_message = "subnet_id must be a full Microsoft.Network/virtualNetworks/.../subnets/... resource id."
  }
}

variable "size" {
  description = "VM size (small burstable tier by default). Must be a Generation 2 size supporting Trusted Launch unless you disable secure_boot_enabled / vtpm_enabled."
  type        = string
  default     = "Standard_B1s"

  validation {
    condition     = can(regex("^Standard_", var.size))
    error_message = "size must be an Azure VM size like Standard_B1s."
  }
}

variable "admin_username" {
  description = "Administrator login for the VM."
  type        = string
  default     = "azureuser"

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_-]{0,31}$", var.admin_username)) && !contains(["admin", "administrator", "root", "guest", "test", "user", "azureuser1"], lower(var.admin_username))
    error_message = "admin_username must be 1-32 lowercase chars starting with a letter or underscore, and must not be a name Azure disallows (admin, administrator, root, guest, test, user)."
  }
}

variable "admin_ssh_public_key" {
  description = "OpenSSH public key for the admin user. Required: password authentication is disabled entirely on this module — a generated password the caller never chose is the one auth path nobody rotates."
  type        = string

  validation {
    condition     = can(regex("^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp256) ", var.admin_ssh_public_key))
    error_message = "admin_ssh_public_key must be an OpenSSH public key (ssh-rsa, ssh-ed25519 or ecdsa-sha2-nistp256). Azure Linux VMs require RSA keys of at least 2048 bits."
  }
}

variable "secure_boot_enabled" {
  description = "Trusted Launch secure boot. On by default; turn off only for a VM size or region that does not support Trusted Launch."
  type        = bool
  default     = true
}

variable "vtpm_enabled" {
  description = "Trusted Launch vTPM, which is what makes boot integrity attestable. On by default; must be on for secure boot to be meaningful."
  type        = bool
  default     = true
}

variable "encryption_at_host_enabled" {
  description = "Encrypt the temp disk and disk caches on the host. Off by default because the EncryptionAtHost subscription feature must be registered first, and apply fails outright if it is not."
  type        = bool
  default     = false
}

variable "os_disk_storage_account_type" {
  description = "OS disk type."
  type        = string
  default     = "Standard_LRS"

  validation {
    condition     = contains(["Standard_LRS", "StandardSSD_LRS", "Premium_LRS", "StandardSSD_ZRS", "Premium_ZRS"], var.os_disk_storage_account_type)
    error_message = "os_disk_storage_account_type must be one of Standard_LRS, StandardSSD_LRS, Premium_LRS, StandardSSD_ZRS, Premium_ZRS."
  }
}

variable "os_disk_size_gb" {
  description = "OS disk size in GiB. Null keeps the image's own size."
  type        = number
  default     = null

  validation {
    # coalesce, not "== null ||": Terraform evaluates both operands of || even when the first is true.
    condition     = coalesce(var.os_disk_size_gb, 30) >= 30 && coalesce(var.os_disk_size_gb, 30) <= 4095
    error_message = "os_disk_size_gb must be null or between 30 and 4095."
  }
}

variable "disk_encryption_set_id" {
  description = "Disk encryption set for customer-managed OS disk encryption. Null uses platform-managed keys — the disk is encrypted either way."
  type        = string
  default     = null
}

variable "network_security_group_id" {
  description = "Network security group to associate with the NIC. Null leaves the subnet's NSG as the only filter; this module never authors NSG rules of its own."
  type        = string
  default     = null
}

variable "assign_system_identity" {
  description = "Give the VM a system-assigned managed identity, so it can reach Key Vault and Storage with no stored credentials."
  type        = bool
  default     = true
}

variable "allow_extension_operations" {
  description = "Allow VM extensions. Needed by the Azure Monitor Agent and by platform patching."
  type        = bool
  default     = true
}

variable "patch_mode" {
  description = "Guest patching mode. AutomaticByPlatform lets Azure install security patches on its own schedule."
  type        = string
  default     = "AutomaticByPlatform"

  validation {
    condition     = contains(["AutomaticByPlatform", "ImageDefault"], var.patch_mode)
    error_message = "patch_mode must be AutomaticByPlatform or ImageDefault (Linux VMs support only these two)."
  }
}

variable "patch_assessment_mode" {
  description = "Patch assessment mode. Must be AutomaticByPlatform whenever patch_mode is."
  type        = string
  default     = "AutomaticByPlatform"

  validation {
    condition     = contains(["AutomaticByPlatform", "ImageDefault"], var.patch_assessment_mode)
    error_message = "patch_assessment_mode must be AutomaticByPlatform or ImageDefault."
  }
}

variable "boot_diagnostics_enabled" {
  description = "Enable managed boot diagnostics (Azure-managed storage, no account of ours)."
  type        = bool
  default     = true
}
