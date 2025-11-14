# Proxmox Authentication Credentials Management
# Reads credentials from libsecret keyring for terraform consumption
# TODO: Consider fancier credential storage (SOPS, Vault, etc.) if needed in future

terraform {
  required_version = ">= 1.0"
  required_providers {
    keyring = {
      source  = "rremer/keyring"
      version = "~> 0.2"
    }
  }
}

# Read Proxmox API tokens from keyring
data "keyring_secret" "terraform_token" {
  name = "proxmox-terraform-token"
}

data "keyring_secret" "csi_token" {
  name = "proxmox-csi-token"
}