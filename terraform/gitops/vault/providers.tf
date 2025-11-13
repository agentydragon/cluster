# Provider configuration for vault module
# Only imports providers actually needed by this module

module "vault_provider" {
  source = "../modules/vault-provider"
}

provider "kubernetes" {
  # Uses in-cluster authentication when running in tofu-controller
}