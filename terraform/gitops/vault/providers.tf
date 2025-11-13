# Provider configuration for vault module

module "common" {
  source        = "../modules/providers"
  vault_enabled = true
  # Uses default vault_address from common module
}

provider "kubernetes" {
  # Uses in-cluster authentication when running in tofu-controller
}

provider "vault" {
  address = "https://vault.test-cluster.agentydragon.com"
  token   = module.common.vault_root_token
}