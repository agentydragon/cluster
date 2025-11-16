# Provider configuration for authentik module
# Only imports providers actually needed by this module

module "vault_provider" {
  source = "../modules/vault-provider"
}

module "authentik_provider" {
  source = "../modules/authentik-provider"
}

provider "kubernetes" {
  # Uses in-cluster authentication when running in tofu-controller
}