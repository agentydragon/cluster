# Provider configuration for authentik module

module "common" {
  source        = "../modules/providers"
  vault_enabled = true
  # Uses defaults from common module
}

provider "kubernetes" {
  # Uses in-cluster authentication when running in tofu-controller
}

provider "vault" {
  address = "https://vault.test-cluster.agentydragon.com"
  token   = module.common.vault_root_token
}

provider "authentik" {
  url   = "https://auth.test-cluster.agentydragon.com"
  token = module.common.authentik_bootstrap_token
}