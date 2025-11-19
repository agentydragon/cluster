# LAYER 3: CONFIGURATION
# Service configuration via external APIs
# Includes: PowerDNS zones/records, SSO provider configurations

# Configure service API providers using credentials
provider "powerdns" {
  server_url = data.terraform_remote_state.services.outputs.service_endpoints.powerdns_url
  api_key    = var.powerdns_api_key
}

provider "authentik" {
  url   = data.terraform_remote_state.services.outputs.service_endpoints.authentik_url
  token = var.authentik_token
}

provider "harbor" {
  url      = data.terraform_remote_state.services.outputs.service_endpoints.harbor_url
  username = "admin"
  password = var.harbor_admin_password
}

provider "gitea" {
  base_url = data.terraform_remote_state.services.outputs.service_endpoints.gitea_url
  token    = var.gitea_admin_token
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

# DNS MODULE: PowerDNS zone and record management
module "dns" {
  source = "../modules/dns"

  cluster_domain = data.terraform_remote_state.infrastructure.outputs.cluster_domain
  cluster_vip    = data.terraform_remote_state.infrastructure.outputs.cluster_vip
  ingress_pool   = "10.0.3.2"
}

# Future: SSO configuration modules can be added here
# module "sso_config" { ... }