# Provider configuration for services module
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

# Harbor provider will be configured once Harbor is deployed with admin credentials
# For now, commented out until we have admin password in Vault
# provider "harbor" {
#   url      = var.harbor_url
#   username = var.harbor_username
#   password = "will-be-configured-later"
# }

# Gitea provider will be configured once Gitea is deployed with admin token
# provider "gitea" {
#   base_url = var.gitea_url
#   token    = "will-be-configured-later"
# }
