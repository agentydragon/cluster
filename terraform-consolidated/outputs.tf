# OUTPUTS for all layers

# PVE-AUTH layer outputs
output "terraform_token" {
  description = "Terraform API token for Proxmox provider"
  value       = local.deploy_pve_auth ? data.external.pve_tokens["terraform"].result.config_json : null
  sensitive   = true
}

output "csi_config" {
  description = "CSI configuration for Proxmox storage"
  value       = local.deploy_pve_auth ? jsondecode(data.external.pve_tokens["csi"].result.config_json) : null
  sensitive   = true
}