terraform {
  required_version = "~> 1.6"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.86.0"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

locals {
  proxmox_api_token = "${var.pm_api_token_id}=${var.pm_api_token_secret}"

  talos_iso_parts   = regex("^([^:]+):(.+)$", var.talos_iso_path)
  talos_iso_storage = local.talos_iso_parts[0]
  talos_iso_volume  = local.talos_iso_parts[1]
  talos_iso_file    = basename(local.talos_iso_volume)
}

provider "proxmox" {
  endpoint  = var.pm_api_url
  insecure  = var.pm_tls_insecure
  api_token = local.proxmox_api_token

  ssh {
    agent    = true
    username = var.proxmox_ssh_username
  }
}

resource "proxmox_virtual_environment_download_file" "talos_iso" {
  content_type = "iso"
  datastore_id = local.talos_iso_storage
  node_name    = var.talos_template_node
  url          = var.talos_iso_url
  file_name    = local.talos_iso_file

  overwrite = true

  lifecycle {
    ignore_changes = [
      overwrite
    ]
  }
}
