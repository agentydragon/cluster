# Provider configuration for authentik module

module "common" {
  source        = "../modules/providers"
  vault_enabled = true
}

provider "kubernetes" {
  # Uses in-cluster authentication when running in tofu-controller
}

provider "vault" {
  address = var.vault_address
  token   = module.common.vault_root_token
}

provider "authentik" {
  url   = var.authentik_url
  token = module.common.authentik_bootstrap_token
}