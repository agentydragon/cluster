locals {
  # Common VM configuration
  vm_config = {
    datastore_id = "local-zfs"
    file_format  = "raw"
    iothread     = true
    ssd          = true
    discard      = "on"
  }

  # Common VM settings
  vm_defaults = {
    bios          = "ovmf"
    machine       = "q35"
    scsi_hardware = "virtio-scsi-single"
    cpu_type      = "host"
    cpu_cores     = 4
    memory_mb     = 4 * 1024
    vga_type      = "qxl"
    tags          = sort(["talos", var.node_type, "kubernetes", "terraform"])
  }

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
      nodeLabels = {
        "topology.kubernetes.io/region" = "cluster"
        "topology.kubernetes.io/zone"   = "atlas"
      }
      kubelet = {
        extraArgs = {
          provider-id = "proxmox://cluster/${var.vm_id}"
        }
        # Explicitly set node IP to prevent conflicts with Tailscale IPs
        nodeIP = {
          validSubnets = ["10.0.0.0/16"] # Cluster network range
        }
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

# Generate unique pre-auth key for this node via SSH
data "external" "preauth_key" {
  program = ["bash", "-c", <<-EOT
    key_json=$(ssh ${var.shared_config.global_config.headscale_server} "headscale preauthkeys create --user ${var.shared_config.global_config.headscale_user} --expiration 1h --output json")
    echo "$key_json" | jq '{key: .key, id: .id}'
  EOT
  ]
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
  tags            = local.vm_defaults.tags
  stop_on_destroy = true
  bios            = local.vm_defaults.bios
  machine         = local.vm_defaults.machine
  scsi_hardware   = local.vm_defaults.scsi_hardware

  operating_system {
    type = "l26"
  }

  cpu {
    type  = local.vm_defaults.cpu_type
    cores = local.vm_defaults.cpu_cores
  }

  memory {
    dedicated = local.vm_defaults.memory_mb
  }

  vga {
    type = local.vm_defaults.vga_type
  }

  network_device {
    bridge = "vmbr0"
  }

  efi_disk {
    datastore_id = local.vm_config.datastore_id
    file_format  = local.vm_config.file_format
    type         = "4m"
  }

  # Use pre-installed Talos disk image as main boot disk
  disk {
    datastore_id = local.vm_config.datastore_id
    interface    = "scsi0"
    iothread     = local.vm_config.iothread
    ssd          = local.vm_config.ssd
    discard      = local.vm_config.discard
    size         = 40
    file_format  = local.vm_config.file_format
    import_from  = proxmox_virtual_environment_download_file.disk_image.id
  }

  # Proxmox CSI uses host storage directly - no additional disks needed

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
      echo "Run: ssh ${var.shared_config.global_config.proxmox_server} 'qm reboot ${var.vm_id}'"
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
    yamlencode(local.common_machine_config) # Common config including tailscale extension and topology labels
    ], var.node_type == "controlplane" ? [
    # Control plane gets VIP configuration at machine generation time
    yamlencode({
      machine = {
        network = {
          interfaces = [{
            interface = "eth0"
            vip       = { ip = var.shared_config.cluster_vip }
          }]
        }
      }
    }),
    # Control plane gets Tailscale configuration baked in at machine generation time
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "ExtensionServiceConfig"
      name       = "tailscale"
      environment = [
        "TS_AUTHKEY=${data.external.preauth_key.result.key}",
        "TS_EXTRA_ARGS=${var.shared_config.tailscale_base_args} ${var.shared_config.tailscale_route_args}"
      ]
    })
    ] : [
    # Workers get Tailscale configuration baked in at machine generation time
    # This avoids the need for runtime patches that trigger the mount controller bug
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "ExtensionServiceConfig"
      name       = "tailscale"
      environment = [
        "TS_AUTHKEY=${data.external.preauth_key.result.key}",
        "TS_EXTRA_ARGS=${var.shared_config.tailscale_base_args}"
      ]
    })
  ])
}

# Apply runtime configuration to the running node (connects via pre-configured IP)
#
# CRITICAL BUG WORKAROUND: Only apply config patches when absolutely necessary
#
# Issue: Talos has a race condition bug in mount controller that causes worker kubelet
# to crash-loop when receiving unnecessary configuration updates during runtime.
#
# Bug details:
# 1. Configuration change triggers kubelet service restart
# 2. Mount requests get torn down during service restart
# 3. Mount controller tries to add finalizer to non-existent mount request
# 4. AddFinalizer() fails because resource was deleted during teardown
# 5. Controller crashes kubelet startup with error:
#    "failed to add finalizer to mount request '/var/log/audit/kube':
#     resource MountRequests.block.talos.dev(runtime//var/log/audit/kube@undefined) doesn't exist"
#
# Root cause: Race condition in mount.go line 196-198:
# https://github.com/siderolabs/talos/blob/main/internal/app/machined/pkg/controllers/block/mount.go#L196-L198
#
# The mount controller assumes mount requests exist when trying to add finalizers,
# but they may have been deleted during the service restart lifecycle.
#
# Workaround: Only send configuration patches to nodes that actually need them.
# Control plane nodes need VIP configuration, workers only need Tailscale on first boot.
#
# TODO: Report this bug upstream to Talos project
resource "talos_machine_configuration_apply" "apply" {
  client_configuration        = var.talos_config_base.machine_secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.config.machine_configuration
  endpoint                    = var.ip_address # Node already has static IP from schematic
  node                        = var.ip_address # Node already has static IP from schematic

  # WORKAROUND: Apply empty config patches to avoid triggering mount controller bug
  # All configuration (VIP, Tailscale) is now baked into machine generation time
  config_patches = []

  depends_on = [proxmox_virtual_environment_vm.vm]
}

# Node registration cleanup on destroy
resource "terraform_data" "node_registration" {
  # Store both pre-auth key ID and server for cleanup
  input = {
    key_id = data.external.preauth_key.result.id
    server = var.shared_config.global_config.headscale_server
  }

  # Cleanup pre-auth key when destroying (nodes auto-expire but keys don't)
  provisioner "local-exec" {
    when    = destroy
    command = "ssh ${self.input.server} 'headscale preauthkeys delete ${self.input.key_id}' || echo 'Pre-auth key ${self.input.key_id} already expired/removed'"
  }

  depends_on = [talos_machine_configuration_apply.apply]
}