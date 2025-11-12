terraform {
  required_version = "~> 1.6"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.86.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.9.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4.0"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3.0"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

# see https://registry.terraform.io/providers/bpg/proxmox/latest/docs#argument-reference
# see environment variables at https://github.com/bpg/terraform-provider-proxmox/blob/v0.84.1/proxmoxtf/provider/provider.go#L52-L61
provider "proxmox" {
  endpoint  = var.pm_api_url
  insecure  = var.pm_tls_insecure
  api_token = "${local.vault_secrets.vault_proxmox_terraform_token_id}=${local.vault_secrets.vault_proxmox_terraform_token_secret}"

  ssh {
    agent       = false
    username    = var.proxmox_ssh_username
    private_key = file("~/.ssh/id_ed25519")
    node {
      name    = "atlas"
      address = "atlas"
    }
  }
}
