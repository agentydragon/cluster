# Test VM using Talos Image Factory ISO
locals {
  talos_version = "v1.11.2"
  schematic_yaml = yamlencode({
    customization = {
      extraKernelArgs = ["net.ifnames=0"]
      systemExtensions = {
        officialExtensions = [
          "siderolabs/qemu-guest-agent",
          "siderolabs/tailscale"
        ]
      }
    }
  })
}

# Create schematic in Image Factory
data "http" "create_schematic" {
  url    = "https://factory.talos.dev/schematics"
  method = "POST"
  request_headers = {
    "Content-Type" = "application/x-yaml"
  }
  request_body = local.schematic_yaml
}

locals {
  schematic_response = jsondecode(data.http.create_schematic.response_body)
  schematic_id       = local.schematic_response.id
  iso_url           = "https://factory.talos.dev/image/${local.schematic_id}/${local.talos_version}/metal-amd64.iso"
}

# Download the Talos ISO from Image Factory
resource "proxmox_virtual_environment_download_file" "talos_iso" {
  content_type = "iso"
  datastore_id = "local"  # Same as working VMs
  node_name    = "atlas"
  url          = local.iso_url
  file_name    = "talos-factory-${local.schematic_id}-${local.talos_version}.iso"
  overwrite    = true
  
  depends_on = [data.http.create_schematic]
}

# Test VM that boots from the ISO
resource "proxmox_virtual_environment_vm" "talos_iso_test" {
  name            = "talos-iso-test"
  node_name       = "atlas"
  tags            = sort(["talos", "iso-test", "terraform"])
  stop_on_destroy = true
  
  # Match working VM configuration exactly
  bios            = "ovmf"
  machine         = "q35"
  scsi_hardware   = "virtio-scsi-single"
  on_boot         = false
  started         = true
  
  operating_system {
    type = "l26"
  }
  
  cpu {
    type  = "host"
    cores = 4  # Match working VMs
  }
  
  memory {
    dedicated = 4 * 1024  # Match working VMs (4GB)
  }
  
  vga {
    type = "qxl"
  }
  
  network_device {
    bridge = "vmbr0"
  }
  
  # EFI disk (like working VMs)
  efi_disk {
    datastore_id = "local-zfs"
    file_format  = "raw"
    type         = "4m"
  }
  
  # Boot from ISO - this will be the key difference
  cdrom {
    enabled   = true
    file_id   = proxmox_virtual_environment_download_file.talos_iso.id
    interface = "ide2"
  }
  
  # Storage disk for Talos installation (like working VMs)
  disk {
    datastore_id = "local-zfs"
    interface    = "scsi0"
    iothread     = true
    ssd          = true
    discard      = "on"
    size         = 40  # Match working VMs
    file_format  = "raw"
  }
  
  # QEMU guest agent (like working VMs)
  agent {
    enabled = true
    trim    = true
  }
  
  # Network initialization (like working VMs)
  initialization {
    datastore_id = "local"
    ip_config {
      ipv4 {
        address = "10.0.0.100/24"  # Test IP
        gateway = "10.0.0.1"
      }
    }
  }
}

# Outputs
output "schematic_id" {
  value = local.schematic_id
  description = "Generated schematic ID from Image Factory"
}

output "iso_url" {
  value = local.iso_url
  description = "ISO download URL from Image Factory"
}