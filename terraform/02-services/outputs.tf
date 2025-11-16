# LAYER 2 OUTPUTS - Service deployment status
# These outputs are consumed by layer 3 for service configuration

# Service deployment status
output "services_deployed" {
  description = "Status of deployed services"
  value = {
    sso_configured = module.gitops.admin_groups
    timestamp      = timestamp()
  }
  sensitive = true
}

# Service endpoints for layer 3 configuration
output "service_endpoints" {
  description = "Service endpoints for API configuration"
  value = {
    authentik_url = "https://authentik.${data.terraform_remote_state.infrastructure.outputs.cluster_domain}"
    harbor_url    = "https://harbor.${data.terraform_remote_state.infrastructure.outputs.cluster_domain}"
    gitea_url     = "https://gitea.${data.terraform_remote_state.infrastructure.outputs.cluster_domain}"
    powerdns_url  = "http://${data.terraform_remote_state.infrastructure.outputs.cluster_vip}:8081"
  }
}

# Readiness indicator for layer 3
output "services_ready_for_configuration" {
  description = "Indicates services are deployed and ready for API configuration"
  value = {
    gitops_complete = module.gitops.admin_groups != null
    cluster_domain  = data.terraform_remote_state.infrastructure.outputs.cluster_domain
    timestamp       = timestamp()
  }
}