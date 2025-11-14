# Proxmox Authentication Credentials Management
# Reads credentials from libsecret keyring via secret-tool for terraform consumption
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

# Read JSON credentials from keyring and parse them
data "external" "keyring" {
  for_each = toset(["proxmox-terraform-token", "proxmox-csi-token"])
  program  = ["bash", "-c", "secret-tool lookup generic-secret name ${each.key}"]
}

# Parse JSON credentials
locals {
  credentials = {
    for name in ["proxmox-terraform-token", "proxmox-csi-token"] :
    name => jsondecode(data.external.keyring[name].result.stdout)
  }
}

# No persistent Headscale API key needed -
# Pre-auth keys are generated directly via SSH in the node module