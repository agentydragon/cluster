# LAYER 3 OUTPUTS - Service configuration status

# DNS configuration status
output "dns_configured" {
  description = "DNS zone and records configured"
  value = {
    cluster_zone = module.dns.cluster_zone
    dns_records  = module.dns.dns_records
    timestamp    = timestamp()
  }
}

# Complete deployment status
output "cluster_fully_configured" {
  description = "Indicates entire cluster is fully configured"
  value = {
    infrastructure_ready = data.terraform_remote_state.infrastructure.outputs.infrastructure_ready
    services_deployed    = data.terraform_remote_state.services.outputs.services_ready_for_configuration
    dns_configured       = module.dns.cluster_zone
    timestamp            = timestamp()
  }
}
