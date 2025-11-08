locals {
  talos_node_defaults = {
    sockets = 1
    tags    = ["talos", "kubernetes"]
  }
}

resource "proxmox_virtual_environment_vm" "talos_nodes" {
  for_each = var.cluster_nodes

  name        = each.value.name
  description = "role=${each.value.role}"
  node_name   = each.value.target_node
  vm_id       = each.value.vm_id
  on_boot     = true
  started     = false

  tags = coalesce(each.value.tags, local.talos_node_defaults.tags)

  machine = "q35"
  bios    = "ovmf"

  cpu {
    sockets = try(each.value.sockets, local.talos_node_defaults.sockets)
    cores   = each.value.cores
    type    = "x86-64-v2-AES"
  }

  memory {
    dedicated = each.value.memory_mb
  }

  efi_disk {
    datastore_id = var.talos_disk_storage
    type         = "4m"
  }

  disk {
    datastore_id = var.talos_disk_storage
    interface    = "scsi0"
    size         = each.value.disk_gb
    discard      = "on"
    iothread     = true
  }

  cdrom {
    file_id   = proxmox_virtual_environment_download_file.talos_iso.id
    interface = "ide2"
  }

  network_device {
    bridge      = each.value.bridge
    mac_address = each.value.mac_address
    vlan_id     = try(each.value.vlan_tag, null)
    model       = "virtio"
  }
}
