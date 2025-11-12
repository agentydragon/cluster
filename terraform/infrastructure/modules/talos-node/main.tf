locals {
  # Create schematic YAML with static IP configuration in META key 0xa (10)
  schematic_yaml = yamlencode({
    customization = {
      extraKernelArgs = ["net.ifnames=0"]
      systemExtensions = {
        officialExtensions = [
          "siderolabs/qemu-guest-agent", 
          "siderolabs/tailscale"
        ]
      }
      meta = [
        {
          key   = 10  # META key 0xa for network configuration  
          value = yamlencode({
            addresses = [
              {
                address   = "${var.ip_address}/16"
                linkName  = "eth0"
                family    = "inet4"
                scope     = "global"
                flags     = "permanent"
                layer     = "platform"
              }
            ]
            routes = [
              {
                family       = "inet4"
                dst          = ""
                gateway      = var.gateway
                outLinkName  = "eth0"
                table        = "main"
                priority     = 1024
                scope        = "global"
                type         = "unicast"
                protocol     = "static"
                layer        = "platform"
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

  # Common machine configuration
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
    }
    cluster = {
      discovery = {
        enabled = false
        registries = {
          kubernetes = { disabled = true }
          service = { disabled = true }
        }
      }
      network = { cni = { name = "none" } }
      proxy = { disabled = true }
    }
  }

  # Tailscale extension configuration
  tailscale_extension_config = {
    machine = {
      install = {
        extensions = [{
          image = "ghcr.io/siderolabs/tailscale:latest"
        }]
      }
    }
    cluster = {}
  }
}

# Generate unique pre-auth key for this node
data "http" "preauth_key" {
  url = "${var.global_config.headscale_login_server}/api/v1/preauthkey"
  method = "POST"
  request_headers = {
    Authorization = "Bearer ${var.global_config.headscale_api_key}"
    Content-Type = "application/json"
  }
  request_body = jsonencode({
    user = "agentydragon"
    reusable = false
    ephemeral = false
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
  talos_version = var.talos_version
  platform      = "metal"
  architecture  = "amd64"
}

# Download the disk image with pre-installed Talos
resource "proxmox_virtual_environment_download_file" "disk_image" {
  content_type = "import"  # Correct content type for disk images
  datastore_id = "local"   # Use local datastore (now configured with import support)
  node_name    = var.proxmox_node_name
  url          = replace(data.talos_image_factory_urls.urls.urls.disk_image, "metal-amd64.raw.zst", "metal-amd64.qcow2")
  file_name    = "talos-${var.node_name}-${var.talos_version}-${substr(sha256(local.schematic_yaml), 0, 8)}.qcow2"
  overwrite    = true
}

# Create the VM
resource "proxmox_virtual_environment_vm" "vm" {
  name            = "${var.prefix}-${var.node_name}"
  vm_id           = var.vm_id
  node_name       = var.proxmox_node_name
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
data "talos_machine_configuration" "config" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_secrets    = var.machine_secrets.machine_secrets
  machine_type       = var.node_type == "controller" ? "controlplane" : "worker"
  talos_version      = "v${var.talos_version}"
  kubernetes_version = var.kubernetes_version
  examples           = false
  docs               = false
  
  config_patches = concat([
    yamlencode(local.common_machine_config),
    yamlencode(local.tailscale_extension_config)
  ], var.node_type == "controller" ? [
    yamlencode({
      machine = {
        network = {
          interfaces = [{
            interface = "eth0"
            vip = { ip = var.cluster_vip }
          }]
        }
      }
    })
  ] : [])
}

# Apply configuration to the node - now enabled since static IP boot is working
resource "talos_machine_configuration_apply" "apply" {
  client_configuration        = var.machine_secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.config.machine_configuration
  endpoint                    = var.ip_address
  node                        = var.ip_address
  
  # Note: Network configuration is now handled by META key 10 in the ISO
  # Only include Tailscale configuration in the runtime patches
  config_patches = [
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "ExtensionServiceConfig"
      name       = "tailscale"
      environment = [
        "TS_AUTHKEY=${jsondecode(data.http.preauth_key.response_body).preAuthKey.key}",
        var.node_type == "controller" ? 
          "TS_EXTRA_ARGS=--login-server=${var.global_config.headscale_login_server} --accept-routes --advertise-routes=10.0.0.0/16" :
          "TS_EXTRA_ARGS=--login-server=${var.global_config.headscale_login_server} --accept-routes"
      ]
    })
  ]
  
  depends_on = [proxmox_virtual_environment_vm.vm]
}