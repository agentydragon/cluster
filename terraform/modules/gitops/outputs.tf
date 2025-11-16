# GITOPS MODULE OUTPUTS

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

output "admin_groups" {
  description = "Created admin groups for services"
  value = {
    harbor_admins = authentik_group.harbor_admins.id
    gitea_admins  = authentik_group.gitea_admins.id
    matrix_admins = authentik_group.matrix_admins.id
  }
}