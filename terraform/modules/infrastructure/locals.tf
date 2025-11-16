terraform {
  required_providers {
    talos = {
      source = "siderolabs/talos"
    }
    helm = {
      source = "hashicorp/helm"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    flux = {
      source = "fluxcd/flux"
    }
    null = {
      source = "hashicorp/null"
    }
    external = {
      source = "hashicorp/external"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}

# CONSOLIDATED LOCALS for all layers

locals {
  # Layer control (already defined in main.tf)

  # PVE-AUTH layer locals (already defined in pve-auth.tf)

  # INFRASTRUCTURE layer locals
  # Host configuration
  hosts = {
    proxmox   = "atlas"
    headscale = "agentydragon.com"
  }

  # SSH targets for auto-provisioning
  ssh_targets = {
    proxmox   = "root@${local.hosts.proxmox}"
    headscale = "root@${local.hosts.headscale}"
  }

  # Network configuration
  networks = {
    cluster_cidr = "10.0.0.0/16"
    gateway      = "10.0.0.1"

    # VIP pools
    cluster_api_vip = "10.0.3.1"
    ingress_pool    = "10.0.3.2"
    dns_pool        = "10.0.3.3"
    services_pool   = "10.0.3.4-20"
  }

}