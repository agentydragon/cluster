# Provider configuration for services module

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
