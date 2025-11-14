# Proxmox Authentication Credentials Management
# Auto-provisions Proxmox users and tokens via SSH for terraform consumption
# TODO: Consider fancier credential storage (SOPS, Vault, etc.) if needed in future

terraform {
  required_version = ">= 1.0"
  required_providers {
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
  }
}

# DRY configuration
locals {
  proxmox_host = "root@atlas"
  users = {
    terraform = {
      name    = "terraform@pve"
      comment = "Terraform automation user"
      role    = "TerraformAdmin"
      privs   = "Datastore.Allocate,Datastore.AllocateSpace,Datastore.Audit,Pool.Allocate,Sys.Audit,Sys.Console,Sys.Modify,VM.Allocate,VM.Audit,VM.Clone,VM.Config.CDROM,VM.Config.CPU,VM.Config.Cloudinit,VM.Config.Disk,VM.Config.HWType,VM.Config.Memory,VM.Config.Network,VM.Config.Options,VM.Console,VM.Migrate,VM.Monitor,VM.PowerMgmt,User.Modify,Permissions.Modify"
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
    token=$(ssh ${local.proxmox_host} '
      # Create user if not exists
      pveum user add ${each.value.name} --comment "${each.value.comment}" 2>/dev/null || true

      # Create role if not exists
      pveum role add ${each.value.role} -privs "${each.value.privs}" 2>/dev/null || true

      # Set ACL permissions
      pveum aclmod / -user ${each.value.name} -role ${each.value.role}

      # Create/recreate API token
      pveum user token delete ${each.value.name} ${each.value.token} 2>/dev/null || true
      pveum user token add ${each.value.name} ${each.value.token} --privsep 0
    ' | grep -E "${each.value.name}!${each.value.token}=" | head -n1)
    echo "{\"token\":\"$token\"}"
  EOT
  ]
}

# No persistent Headscale API key needed -
# Pre-auth keys are generated directly via SSH in the node module