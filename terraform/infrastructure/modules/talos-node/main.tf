locals {
  # Create schematic YAML with static IP configuration in META key 0xa (10)
  schematic_yaml = yamlencode({
    customization = {
      extraKernelArgs = concat(["net.ifnames=0"], var.node_type == "worker" ? ["hugepages=1024"] : [])
      systemExtensions = {
        officialExtensions = [
          "siderolabs/qemu-guest-agent",
          "siderolabs/tailscale",
          "siderolabs/iscsi-tools",
          "siderolabs/util-linux-tools"
        ]
      }
      meta = [
        {
          key = 10 # META key 0xa for network configuration
          value = yamlencode({
            addresses = [
              {
                address  = "${var.ip_address}/16"
                linkName = "eth0"
                family   = "inet4"
                scope    = "global"
                flags    = "permanent"
                layer    = "platform"
              }
            ]
            routes = [
              {
                family      = "inet4"
                dst         = ""
                gateway     = var.shared_config.gateway
                outLinkName = "eth0"
                table       = "main"
                priority    = 1024
                scope       = "global"
                type        = "unicast"
                protocol    = "static"
                layer       = "platform"
              }
            ]
            hostnames = [
              {
                hostname = var.node_name
                layer    = "platform"
              }
            ]
            resolvers = [
              {
                dnsServers = ["1.1.1.1", "8.8.8.8"]
                layer      = "platform"
              }
            ]
          })
        }
      ]
    }
  })

  # Common machine configuration (includes Tailscale extension)
  common_machine_config = {
    machine = {
      features = {
        kubePrism = {
          enabled = true
          port    = 7445
        }
        hostDNS = {
          enabled              = true
          forwardKubeDNSToHost = true
        }
      }
      kernel = {
        modules = [
          {
            name = "nbd"
          },
          {
            name = "iscsi_tcp"
          },
          {
            name = "configfs"
          }
        ]
      }
      kubelet = {
        # Note: extraMounts not needed for raw block device usage
        # Longhorn will access /dev/sdb directly
        extraMounts = []
      }
    }
    cluster = {
      discovery = {
        enabled = false
        registries = {
          kubernetes = { disabled = true }
          service    = { disabled = true }
        }
      }
      network = { cni = { name = "none" } }
      proxy   = { disabled = true }
    }
  }
}

# Generate unique pre-auth key for this node
data "http" "preauth_key" {
  url    = "${var.shared_config.global_config.headscale_login_server}/api/v1/preauthkey"
  method = "POST"
  request_headers = {
    Authorization = "Bearer ${var.shared_config.global_config.headscale_api_key}"
    Content-Type  = "application/json"
  }
  request_body = jsonencode({
    user       = var.shared_config.global_config.headscale_user
    reusable   = false
    ephemeral  = false
    expiration = timeadd(timestamp(), "1h")
  })
}

# Create schematic in Image Factory using Talos provider
resource "talos_image_factory_schematic" "schematic" {
  schematic = local.schematic_yaml
}

# Generate URLs for different image formats
data "talos_image_factory_urls" "urls" {
  schematic_id  = talos_image_factory_schematic.schematic.id
  talos_version = var.talos_config_base.talos_version
  platform      = "metal"
  architecture  = "amd64"
}

# Download the disk image with pre-installed Talos
resource "proxmox_virtual_environment_download_file" "disk_image" {
  content_type = "import" # Correct content type for disk images
  datastore_id = "local"  # Use local datastore (now configured with import support)
  node_name    = var.shared_config.proxmox_node_name
  url          = replace(data.talos_image_factory_urls.urls.urls.disk_image, "metal-amd64.raw.zst", "metal-amd64.qcow2")
  file_name    = "talos-${talos_image_factory_schematic.schematic.id}-amd64.qcow2"
  overwrite    = true
}

# Create the VM
resource "proxmox_virtual_environment_vm" "vm" {
  name            = "${var.shared_config.prefix}-${var.node_name}"
  vm_id           = var.vm_id
  node_name       = var.shared_config.proxmox_node_name
  tags            = sort(["talos", var.node_type, "kubernetes", "terraform"])
  stop_on_destroy = true
  bios            = "ovmf"
  machine         = "q35"
  scsi_hardware   = "virtio-scsi-single"

  operating_system {
    type = "l26"
  }

  cpu {
    type  = "host"
    cores = 4
  }

  memory {
    dedicated = 4 * 1024
  }

  vga {
    type = "qxl"
  }

  network_device {
    bridge = "vmbr0"
  }

  efi_disk {
    datastore_id = "local-zfs"
    file_format  = "raw"
    type         = "4m"
  }

  # Use pre-installed Talos disk image as main boot disk
  disk {
    datastore_id = "local-zfs"
    interface    = "scsi0"
    iothread     = true
    ssd          = true
    discard      = "on"
    size         = 40
    file_format  = "raw"
    import_from  = proxmox_virtual_environment_download_file.disk_image.id
  }

  # Dedicated storage disk for Longhorn (worker nodes only)
  dynamic "disk" {
    for_each = var.node_type == "worker" ? [1] : []
    content {
      datastore_id = "local-zfs"
      interface    = "scsi1"
      iothread     = true
      ssd          = true
      discard      = "on"
      size         = 128
      file_format  = "raw"
      serial       = "lh-${var.node_name}" # Stable identifier (max 20 chars)
    }
  }

  agent {
    enabled = true
    trim    = true
  }
  # NOTE: Static IP and Talos OS are pre-baked into the disk image
}

# Print restart reminder when disk image changes
resource "terraform_data" "restart_reminder" {
  triggers_replace = [
    proxmox_virtual_environment_download_file.disk_image.id
  ]

  provisioner "local-exec" {
    command = <<-EOT
      echo ""
      echo "⚠️  RESTART REQUIRED for VM ${var.vm_id} (${var.node_name}) ⚠️"
      echo "Disk image changed: ${proxmox_virtual_environment_download_file.disk_image.file_name}"
      echo "Run: ssh root@atlas 'qm reboot ${var.vm_id}'"
      echo ""
    EOT
  }

  depends_on = [proxmox_virtual_environment_vm.vm]
}

# Generate machine configuration based on node type
# This is as close as Terraform gets to "take this object + add these fields"
locals {
  # Merge base talos config + node-specific machine_type
  machine_config = merge(
    var.talos_config_base, # All the shared talos fields
    {
      machine_type    = var.node_type                                         # Node-specific override
      machine_secrets = var.talos_config_base.machine_secrets.machine_secrets # Extract the actual secrets
    }
  )
}

data "talos_machine_configuration" "config" {
  # Unfortunately Terraform doesn't support object splatting in resources
  # This repetition is unavoidable but at least it's explicit
  cluster_name       = local.machine_config.cluster_name
  cluster_endpoint   = local.machine_config.cluster_endpoint
  machine_secrets    = local.machine_config.machine_secrets
  machine_type       = local.machine_config.machine_type
  talos_version      = local.machine_config.talos_version
  kubernetes_version = local.machine_config.kubernetes_version
  examples           = local.machine_config.examples
  docs               = local.machine_config.docs

  config_patches = concat([
    yamlencode(local.common_machine_config) # Now includes tailscale extension
    ], var.node_type == "controlplane" ? [
    yamlencode({
      machine = {
        network = {
          interfaces = [{
            interface = "eth0"
            vip       = { ip = var.shared_config.cluster_vip }
          }]
        }
      }
    })
    ] : var.node_type == "worker" ? [
    yamlencode({
      machine = {
        nodeLabels = {
          "node.longhorn.io/create-default-disk" = "config"
        }
        nodeAnnotations = {
          "node.longhorn.io/default-disks-config" = "[{\"path\":\"/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_lh-${var.node_name}\", \"allowScheduling\": true, \"diskType\": \"block\"}]"
        }
      }
    })
  ] : [])
}

# Apply runtime configuration to the running node (connects via pre-configured IP)
resource "talos_machine_configuration_apply" "apply" {
  client_configuration        = var.talos_config_base.machine_secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.config.machine_configuration
  endpoint                    = var.ip_address # Node already has static IP from schematic
  node                        = var.ip_address # Node already has static IP from schematic

  # Apply runtime patches (Tailscale service config with dynamic auth keys)
  # Network/IP configuration is already handled by schematic META key during boot
  config_patches = [
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "ExtensionServiceConfig"
      name       = "tailscale"
      environment = [
        "TS_AUTHKEY=${jsondecode(data.http.preauth_key.response_body).preAuthKey.key}",
        "TS_EXTRA_ARGS=${var.shared_config.tailscale_base_args}${var.node_type == "controlplane" ? " ${var.shared_config.tailscale_route_args}" : ""}"
      ]
    })
  ]

  depends_on = [proxmox_virtual_environment_vm.vm]
}



