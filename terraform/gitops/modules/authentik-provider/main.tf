# Authentik provider module
terraform {
  required_providers {
    authentik = {
      source  = "goauthentik/authentik"
      version = "~> 2025.1"
    }
  }
}

# Import common data sources for authentik credentials
module "common" {
  source        = "../common"
  vault_enabled = true
}

# Configure the Authentik provider
provider "authentik" {
  url   = var.authentik_url
  token = module.common.authentik_bootstrap_token
}