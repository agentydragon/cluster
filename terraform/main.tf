# CONSOLIDATED CLUSTER TERRAFORM - PROPER MODULE STRUCTURE
# Single terraform managing all cluster layers with proper dependencies

# PROVIDER CONFIGURATIONS - Basic providers only (no circular dependencies)
# Complex providers are configured within their respective modules

# PVE-AUTH MODULE: Creates Proxmox users and API tokens
module "pve_auth" {
  source = "./modules/pve-auth"

  proxmox_host     = var.proxmox_host
  proxmox_api_host = var.proxmox_api_host
}

# INFRASTRUCTURE MODULE: Creates Talos cluster, CNI, and Flux GitOps
module "infrastructure" {
  source     = "./modules/infrastructure"
  depends_on = [module.pve_auth]

  # Pass PVE auth outputs
  proxmox_token     = module.pve_auth.terraform_token
  csi_config        = module.pve_auth.csi_config
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

  # GitHub for Flux GitOps
  github_owner      = var.github_owner
  github_repository = var.github_repository
}

# STORAGE MODULE: Generates CSI secrets for persistent storage
module "storage" {
  source     = "./modules/storage"
  depends_on = [module.infrastructure]

  csi_config = module.pve_auth.csi_config
}

# GITOPS MODULE: SSO services (Authentik, Vault, Harbor, Gitea, Matrix)
module "gitops" {
  source     = "./modules/gitops"
  depends_on = [module.infrastructure]

  kubeconfig      = module.infrastructure.kubeconfig
  cluster_domain  = var.cluster_domain
  vault_address   = "http://vault.vault.svc.cluster.local:8200"
  authentik_url   = "https://authentik.${var.cluster_domain}"
  authentik_token = "" # Will be set via environment variable
}

# DNS MODULE: PowerDNS zone and record management
module "dns" {
  source     = "./modules/dns"
  depends_on = [module.infrastructure, module.gitops]

  cluster_domain      = var.cluster_domain
  cluster_vip         = var.cluster_vip
  ingress_pool        = "10.0.3.2"
  powerdns_server_url = "http://powerdns.dns-system.svc.cluster.local:8081"
  powerdns_api_key    = "" # Will be retrieved from Vault
}