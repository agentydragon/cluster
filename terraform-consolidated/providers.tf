# PROVIDER CONFIGURATIONS for all layers

# PVE-AUTH dependencies: none (uses ssh via external data source)

# INFRASTRUCTURE layer providers
# Read Proxmox credentials from pve-auth layer when available
provider "proxmox" {
  endpoint  = local.deploy_pve_auth ? jsondecode(data.external.pve_tokens["terraform"].result.config_json).url : "https://${var.proxmox_api_host}/api2/json"
  insecure  = local.deploy_pve_auth ? jsondecode(data.external.pve_tokens["terraform"].result.config_json).insecure : false
  api_token = local.deploy_pve_auth ? jsondecode(data.external.pve_tokens["terraform"].result.config_json).token : ""
}

provider "helm" {
  kubernetes {
    config_path = local.kubeconfig_path
  }
}

provider "kubernetes" {
  config_path = local.kubeconfig_path
}

provider "flux" {
  kubernetes = {
    config_path = local.kubeconfig_path
  }
  git = {
    url = "https://github.com/${var.github_owner}/${var.github_repository}.git"
    http = {
      username = "git"
      password = local.deploy_infrastructure ? data.external.github_token[0].result.token : ""
    }
  }
}

# DNS layer providers
provider "powerdns" {
  api_key    = "" # Will be set via variables when DNS layer is active
  server_url = "" # Will be set via variables when DNS layer is active
}

# VAULT provider (for gitops secrets)
provider "vault" {
  # Configuration will be added when gitops layer is implemented
}

# AUTHENTIK provider (for gitops SSO)
provider "authentik" {
  # Configuration will be added when gitops layer is implemented
}