# Placeholder for vault terraform config
# This will be implemented later for non-SSO vault configuration
terraform {
  required_providers {
    vault = {
      source = "hashicorp/vault"
    }
  }

  backend "kubernetes" {
    secret_suffix = "vault-config"
    namespace     = "flux-system"
  }
}

provider "vault" {
  address = var.vault_address
}

# TODO: Add vault configuration resources here
# This is currently a placeholder to satisfy the terraform path dependency