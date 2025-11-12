# Shared data sources for GitOps modules

# Extract Vault root token from Kubernetes secret
data "kubernetes_secret" "vault_root_token" {
  metadata {
    name      = "vault-root-token"
    namespace = "vault"
  }
}

# Read Authentik bootstrap token from Vault (if vault_enabled)
data "vault_kv_secret_v2" "authentik_secrets" {
  count = var.vault_enabled ? 1 : 0
  mount = "kv"
  name  = "sso/authentik"
}