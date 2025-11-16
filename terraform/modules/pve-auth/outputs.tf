# PVE-AUTH MODULE OUTPUTS

output "terraform_token" {
  description = "Terraform API token for Proxmox provider"
  value       = data.external.pve_tokens["terraform"].result.config_json
  sensitive   = true
}

output "csi_config" {
  description = "CSI configuration for Proxmox storage"
  value       = jsondecode(data.external.pve_tokens["csi"].result.config_json)
  sensitive   = true
}