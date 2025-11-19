# LAYER 3: DNS ZONE MANAGEMENT
# Manages PowerDNS zones and records for cluster domain
# Note: SSO configurations are managed separately via terraform/authentik-blueprint/ (tofu-controller)

# Configure PowerDNS provider
provider "powerdns" {
  server_url = data.terraform_remote_state.services.outputs.service_endpoints.powerdns_url
  api_key    = var.powerdns_api_key
}

# DNS MODULE: PowerDNS zone and record management
module "dns" {
  source = "../modules/dns"

  cluster_domain = data.terraform_remote_state.infrastructure.outputs.cluster_domain
  cluster_vip    = data.terraform_remote_state.infrastructure.outputs.cluster_vip
  ingress_pool   = "10.0.3.2"
}