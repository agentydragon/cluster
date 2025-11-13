# Vault provider module
terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.5"
    }
  }
}

# Import common data sources for vault credentials
module "common" {
  source = "../common"
}

# Configure the Vault provider
provider "vault" {
  address = var.vault_address
  token   = module.common.vault_root_token
}