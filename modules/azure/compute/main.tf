# Opinionated small-tier Linux VM: Trusted Launch (secure boot + vTPM), no public IP, platform patching, boot diagnostics, system-assigned identity, SSH-key-only auth. Host encryption and CMK optional.

resource "azurerm_network_interface" "this" {
  name                = "${var.name}-nic"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  # A VM that forwards IP can be turned into a router between subnets.
  ip_forwarding_enabled = false

  ip_configuration {
    name                          = "primary"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    # public_ip_address_id is deliberately never set: this module attaches no public IP.
  }
}

resource "azurerm_network_interface_security_group_association" "this" {
  count = var.network_security_group_id == null ? 0 : 1

  network_interface_id      = azurerm_network_interface.this.id
  network_security_group_id = var.network_security_group_id
}

resource "azurerm_linux_virtual_machine" "this" {
  name                  = var.name
  resource_group_name   = var.resource_group_name
  location              = var.location
  size                  = var.size
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.this.id]
  tags                  = var.tags

  # SSH-key-only: no password exists to brute-force, leak through an output, or forget to rotate.
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }

  # Trusted Launch: measured boot plus a vTPM, so bootkit tampering is detectable.
  secure_boot_enabled = var.secure_boot_enabled
  vtpm_enabled        = var.vtpm_enabled

  # Encrypts the VM's temp disk and disk caches on the host itself, not just the managed disk.
  encryption_at_host_enabled = var.encryption_at_host_enabled

  provision_vm_agent         = true
  allow_extension_operations = var.allow_extension_operations
  patch_mode                 = var.patch_mode
  patch_assessment_mode      = var.patch_assessment_mode

  dynamic "identity" {
    for_each = var.assign_system_identity ? [1] : []

    content {
      type = "SystemAssigned"
    }
  }

  # Managed boot diagnostics: the only way to see a boot failure without console access.
  dynamic "boot_diagnostics" {
    for_each = var.boot_diagnostics_enabled ? [1] : []

    content {}
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.os_disk_storage_account_type
    disk_size_gb         = var.os_disk_size_gb
    # Managed disks are always encrypted; a disk encryption set moves key ownership to the caller.
    disk_encryption_set_id = var.disk_encryption_set_id
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  lifecycle {
    precondition {
      condition     = var.patch_mode != "AutomaticByPlatform" || var.patch_assessment_mode == "AutomaticByPlatform"
      error_message = "patch_mode = AutomaticByPlatform requires patch_assessment_mode = AutomaticByPlatform."
    }
  }
}
