# Output Proxmox credentials for consumption by other terraform modules

output "terraform_token" {
  description = "Proxmox terraform API token (id=secret format)"
  value       = jsondecode(data.external.tokens["terraform"].result.config_json).token
  sensitive   = true
}

output "csi_config" {
  description = "Complete Proxmox CSI cluster configuration as JSON string"
  value       = jsondecode(data.external.tokens["csi"].result.config_json)
  sensitive   = true
}