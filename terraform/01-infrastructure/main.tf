# LAYER 1: INFRASTRUCTURE
# Pure infrastructure deployment - no external service APIs
# Includes: PVE auth, VMs, Talos cluster, CNI, storage, Vault

# Proxmox provider using credentials from pve-auth module
provider "proxmox" {
  endpoint = "https://${var.proxmox_api_host}:8006/"
  username = "terraform@pve"
  # Parse the token from the JSON config returned by pve-auth module
  api_token = jsondecode(module.pve_auth.terraform_token)["token"]
  insecure  = true # Dev environment with self-signed certs
}

# PVE-AUTH MODULE: Creates Proxmox users and API tokens
module "pve_auth" {
  source = "../modules/pve-auth"

  proxmox_host     = var.proxmox_host
  proxmox_api_host = var.proxmox_api_host
}

# INFRASTRUCTURE MODULE: Creates Talos cluster, CNI, and Flux GitOps
module "infrastructure" {
  source     = "../modules/infrastructure"
  depends_on = [module.pve_auth]

  proxmox_node_name = var.proxmox_node_name

  # Cluster configuration
  cluster_name       = var.cluster_name
  cluster_vip        = var.cluster_vip
  cluster_networks   = var.cluster_networks
  controller_count   = var.controller_count
  worker_count       = var.worker_count
  prefix             = var.prefix
  vm_id_ranges       = var.vm_id_ranges
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version

  # Headscale/Tailscale integration
  headscale_user         = var.headscale_user
  headscale_login_server = var.headscale_login_server
}

# STORAGE MODULE: Generates CSI secrets for persistent storage
module "storage" {
  source     = "../modules/storage"
  depends_on = [module.infrastructure]

  csi_config = module.pve_auth.csi_config
}