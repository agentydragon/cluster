# Global configuration and constants
# Centralized location for all cluster-wide settings

# TODO: Add post-destroy cleanup for orphaned Proxmox CSI disks - WITH SAFETY
# With reclaimPolicy: "Retain", CSI volumes persist after terraform destroy
# CRITICAL: Must only delete volumes belonging to THIS cluster (VM IDs 1500-1502, 2000-2002)
# Consider adding: ssh root@atlas 'pvesm list local-zfs | grep -E "vm-(1500|1501|1502|2000|2001|2002)-disk-[2-9]" | awk "{print \$1}" | xargs -r -I {} pvesm free local-zfs:{} || true'
# Alternative: Use Proxmox tags or notes to identify cluster-owned volumes for safer cleanup
# This would clean up accumulated CSI volumes ONLY from our cluster, never touching other VMs

# Sealed-secrets keypair generation moved to sealed-secrets-keypair.tf
# Generates deterministic keypair that survives destroy/apply cycles

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