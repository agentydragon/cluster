# Global configuration and constants
# Centralized location for all cluster-wide settings

locals {
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

  # API URLs
  api_urls = {
    pve = "https://${local.hosts.proxmox}:8006/api2/json"
  }

  # Common tags for resources
  common_tags = ["terraform", "talos", "kubernetes"]
}