# Proxmox Authentication Credentials Management
# Auto-provisions Proxmox users and tokens via SSH for terraform consumption
# TODO: Consider fancier credential storage (SOPS, Vault, etc.) if needed in future

# Version constraints inherited from /terraform/versions.tf

# Variables
variable "proxmox_host" {
  description = "Proxmox host for SSH access"
  type        = string
  default     = "atlas"
}

variable "proxmox_api_host" {
  description = "Proxmox API host FQDN"
  type        = string
  default     = "atlas.agentydragon.com"
}

# DRY configuration
locals {
  proxmox_host = "root@${var.proxmox_host}"
  users = {
    terraform = {
      name    = "terraform@pve"
      comment = "Terraform automation user"
      role    = "TerraformAdmin"
      privs   = "Datastore.Allocate,Datastore.AllocateSpace,Datastore.AllocateTemplate,Datastore.Audit,Pool.Allocate,SDN.Use,Sys.Audit,Sys.Console,Sys.Modify,VM.Allocate,VM.Audit,VM.Clone,VM.Config.CDROM,VM.Config.CPU,VM.Config.Cloudinit,VM.Config.Disk,VM.Config.HWType,VM.Config.Memory,VM.Config.Network,VM.Config.Options,VM.Console,VM.Migrate,VM.Monitor,VM.PowerMgmt,User.Modify,Permissions.Modify"
      token   = "terraform-token"
    }
    csi = {
      name    = "kubernetes-csi@pve"
      comment = "Kubernetes CSI driver service account"
      role    = "CSI"
      privs   = "VM.Audit,VM.Config.Disk,Datastore.Allocate,Datastore.AllocateSpace,Datastore.Audit"
      token   = "csi"
    }
  }
}

# Auto-provision Proxmox users and tokens via SSH
data "external" "tokens" {
  for_each = local.users
  program = ["bash", "-c", <<-EOT
    token_json=$(ssh ${local.proxmox_host} '
      # Create user if not exists
      pveum user add ${each.value.name} --comment "${each.value.comment}" 2>/dev/null || true

      # Create role if not exists
      pveum role add ${each.value.role} -privs "${each.value.privs}" 2>/dev/null || true

      # Set ACL permissions
      pveum aclmod / -user ${each.value.name} -role ${each.value.role}

      # Create/recreate API token with JSON output
      pveum user token delete ${each.value.name} ${each.value.token} 2>/dev/null || true
      pveum user token add ${each.value.name} ${each.value.token} --privsep 0 --output-format json
    ')
    # Extract the token value and create complete CSI configuration
    token_value=$(echo "$token_json" | jq -r '.value')
    token_id="${each.value.name}!${each.value.token}"

    # Create CSI config JSON and properly escape it as a string
    csi_config_json=$(cat <<JSON
{"url":"https://${var.proxmox_api_host}/api2/json","insecure":false,"token_id":"$token_id","token_secret":"$token_value","region":"cluster","token":"$token_id=$token_value"}
JSON
)
    # Output for terraform external - wrap JSON as escaped string
    printf '{"config_json":"%s"}' "$(echo "$csi_config_json" | sed 's/"/\\"/g')"
  EOT
  ]
}

# Deprovisioning: Clean up Proxmox tokens and users on destroy
resource "null_resource" "cleanup_proxmox_tokens" {
  for_each = local.users

  # Store values needed for destroy provisioner (can only use self.* in destroy)
  triggers = {
    user_name    = each.value.name
    token_name   = each.value.token
    role_name    = each.value.role
    proxmox_host = local.proxmox_host
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "Cleaning up Proxmox user and token: ${self.triggers.user_name}"
      ssh ${self.triggers.proxmox_host} '
        # Delete API token
        pveum user token delete ${self.triggers.user_name} ${self.triggers.token_name} 2>/dev/null || true

        # Delete user (this will also remove ACL entries)
        pveum user delete ${self.triggers.user_name} 2>/dev/null || true

        # Delete role if no other users are using it
        if ! pveum user list | grep -q "@pve" || [ "$(pveum aclmod / -role ${self.triggers.role_name} 2>/dev/null | wc -l)" -eq 0 ]; then
          pveum role delete ${self.triggers.role_name} 2>/dev/null || true
        fi

        echo "Cleanup completed for ${self.triggers.user_name}"
      '
    EOT
  }

  depends_on = [data.external.tokens]
}

# No persistent Headscale API key needed -
# Pre-auth keys are generated directly via SSH in the node module