# Output Proxmox credentials for consumption by other terraform modules

output "terraform_token" {
  description = "Proxmox terraform API token (id=secret format)"
  value       = data.external.tokens["terraform"].result.token
  sensitive   = true
}

output "csi_config" {
  description = "Complete Proxmox CSI cluster configuration"
  value       = data.external.tokens["csi"].result
  sensitive   = true
}