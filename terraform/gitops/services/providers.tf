# Read secrets from Vault for provider authentication
data "kubernetes_secret" "vault_root_token" {
  metadata {
    name      = "vault-root-token"
    namespace = "vault"
  }
}

data "vault_kv_secret_v2" "authentik_secrets" {
  mount = "kv"
  name  = "sso/authentik"
}

# For now, we'll use admin password from Harbor secret (need to generate this first)
# This will be created by the Harbor deployment process

# Provider configurations
provider "vault" {
  address = var.vault_address
  token   = data.kubernetes_secret.vault_root_token.data["root-token"]
}

provider "authentik" {
  url   = var.authentik_url
  token = data.vault_kv_secret_v2.authentik_secrets.data["bootstrap-token"]
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

provider "kubernetes" {
  config_path = var.kubeconfig_path
}
