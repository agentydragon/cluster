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

  # Handle ACL cleanup gracefully since we manage ACLs via SSH
  lifecycle {
    create_before_destroy = true
  }
}

# Create API token for CSI authentication
resource "proxmox_virtual_environment_user_token" "csi" {
  user_id    = proxmox_virtual_environment_user.csi.user_id
  token_name = "csi"
  comment    = "Kubernetes CSI API token"

  # Disable privilege separation - token inherits user's full permissions
  privileges_separation = false
}

# Grant CSI role to CSI user at root level via SSH
# Using SSH because terraform API token lacks Permissions.Modify on root path
resource "null_resource" "csi_acl" {
  provisioner "remote-exec" {
    inline = [
      "pveum aclmod / -user kubernetes-csi@pve -role CSI"
    ]

    connection {
      type        = "ssh"
      user        = "root"
      host        = "atlas"
      private_key = file("/home/agentydragon/.ssh/id_ed25519")
      timeout     = "2m"
    }
  }

  # Clean up ACL before user deletion to prevent permission errors
  provisioner "remote-exec" {
    when = destroy
    inline = [
      "pveum acl delete / -user kubernetes-csi@pve -role CSI || true"
    ]

    connection {
      type        = "ssh"
      user        = "root"
      host        = "atlas"
      private_key = file("/home/agentydragon/.ssh/id_ed25519")
      timeout     = "2m"
    }
  }

  depends_on = [
    proxmox_virtual_environment_user.csi,
    proxmox_virtual_environment_role.csi,
    proxmox_virtual_environment_user_token.csi
  ]
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