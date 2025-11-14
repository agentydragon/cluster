# Proxmox CSI Driver Authentication
# Uses pre-created credentials from pve-auth module

# Output complete CSI configuration for storage terraform
output "proxmox_csi_config" {
  description = "Complete Proxmox CSI configuration"
  value       = data.terraform_remote_state.pve_auth.outputs.csi_config
  sensitive   = true
}