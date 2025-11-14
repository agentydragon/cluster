# Proxmox CSI Driver Authentication
# Uses pre-created credentials from pve-auth module

# Output CSI credentials for Kubernetes secret creation
output "proxmox_csi_token" {
  description = "Proxmox CSI token for Kubernetes secret"
  value       = data.terraform_remote_state.pve_auth.outputs.csi_token
  sensitive   = true
}

output "proxmox_csi_api_url" {
  description = "Proxmox API URL for CSI configuration"
  value       = data.terraform_remote_state.pve_auth.outputs.pve_api_url
  sensitive   = false
}

output "proxmox_tls_insecure" {
  description = "Proxmox TLS insecure setting for CSI configuration"
  value       = data.terraform_remote_state.pve_auth.outputs.tls_insecure
  sensitive   = false
}