# Common data sources module - no providers, just shared data

# Get vault root token from k8s secret
data "kubernetes_secret" "vault_root_token" {
  metadata {
    name      = "vault-unseal-keys"
    namespace = "vault"
  }
}

# Get authentik secrets from vault (only if vault is available)
data "vault_kv_secret_v2" "authentik_secrets" {
  count = var.vault_enabled ? 1 : 0
  mount = "kvv2"
  name  = "authentik"
}