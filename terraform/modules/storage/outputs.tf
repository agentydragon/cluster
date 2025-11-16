# STORAGE MODULE OUTPUTS

output "csi_secret_generated" {
  description = "Whether CSI secret was generated successfully"
  value       = null_resource.proxmox_csi_secret.id != null
}