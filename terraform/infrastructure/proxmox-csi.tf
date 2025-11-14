# Proxmox CSI Driver Authentication Resources
# Creates minimal-privilege user for Kubernetes CSI operations

# Create CSI-specific role with minimal required privileges
resource "proxmox_virtual_environment_role" "csi" {
  role_id = "CSI"

  privileges = [
    # VM disk management (attach/detach volumes)
    "VM.Audit",
    "VM.Config.Disk",

    # Storage allocation and management
    "Datastore.Allocate",
    "Datastore.AllocateSpace",
    "Datastore.Audit",
  ]
}

# Create dedicated CSI user
resource "proxmox_virtual_environment_user" "csi" {
  user_id = "kubernetes-csi@pve"
  comment = "Kubernetes CSI driver service account"
  enabled = true
}

# Create API token for CSI authentication
resource "proxmox_virtual_environment_user_token" "csi" {
  user_id    = proxmox_virtual_environment_user.csi.user_id
  token_name = "csi"
  comment    = "Kubernetes CSI API token"

  # Disable privilege separation - token inherits user's full permissions
  privileges_separation = false
}

# Grant CSI role to CSI user at root level
resource "proxmox_virtual_environment_acl" "csi" {
  path      = "/"
  user_id   = proxmox_virtual_environment_user.csi.user_id
  role_id   = proxmox_virtual_environment_role.csi.role_id
  propagate = true
}

# Output CSI credentials for Kubernetes secret creation
output "proxmox_csi_token_id" {
  description = "Proxmox CSI token ID for Kubernetes secret"
  value       = "${proxmox_virtual_environment_user.csi.user_id}!${proxmox_virtual_environment_user_token.csi.token_name}"
  sensitive   = false
}

output "proxmox_csi_token_secret" {
  description = "Proxmox CSI token secret for Kubernetes secret"
  value       = proxmox_virtual_environment_user_token.csi.value
  sensitive   = true
}

output "proxmox_csi_api_url" {
  description = "Proxmox API URL for CSI configuration"
  value       = "https://${var.proxmox_node_name}:8006/api2/json"
  sensitive   = false
}

output "proxmox_tls_insecure" {
  description = "Proxmox TLS insecure setting for CSI configuration"
  value       = var.proxmox_tls_insecure
  sensitive   = false
}