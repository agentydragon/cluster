# Outputs from common data sources

output "vault_root_token" {
  description = "Vault root token from Kubernetes secret"
  value       = data.kubernetes_secret.vault_root_token.data["root-token"]
  sensitive   = true
}

output "authentik_bootstrap_token" {
  description = "Authentik bootstrap token from Vault"
  value       = var.vault_enabled ? data.vault_kv_secret_v2.authentik_secrets[0].data["bootstrap-token"] : null
  sensitive   = true
}