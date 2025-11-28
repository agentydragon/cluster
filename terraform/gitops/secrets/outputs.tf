output "harbor_client_secret" {
  description = "Harbor OIDC client secret"
  value       = random_password.harbor_client_secret.result
  sensitive   = true
}

output "gitea_client_secret" {
  description = "Gitea OIDC client secret"
  value       = random_password.gitea_client_secret.result
  sensitive   = true
}

output "matrix_client_secret" {
  description = "Matrix OIDC client secret"
  value       = random_password.matrix_client_secret.result
  sensitive   = true
}

output "vault_client_secret" {
  description = "Vault OIDC client secret"
  value       = random_password.vault_client_secret.result
  sensitive   = true
}

output "grafana_client_secret" {
  description = "Grafana OIDC client secret"
  value       = random_password.grafana_client_secret.result
  sensitive   = true
}