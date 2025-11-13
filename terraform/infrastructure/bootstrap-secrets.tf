locals {
  cluster_root = "${path.module}/../.."
}

module "vault_bootstrap_secret" {
  source = "./modules/bootstrap-secret"

  name         = "vault-bootstrap"
  namespace    = "vault"
  secret_key   = "root-token"
  service_name = "vault"
  cluster_root = local.cluster_root

  depends_on = [null_resource.flux_bootstrap]
}

module "authentik_bootstrap_secret" {
  source = "./modules/bootstrap-secret"

  name         = "authentik-bootstrap"
  namespace    = "authentik"
  secret_key   = "bootstrap-token"
  service_name = "authentik"
  cluster_root = local.cluster_root

  depends_on = [null_resource.flux_bootstrap]
}

# Summary output
resource "null_resource" "bootstrap_summary" {
  depends_on = [
    module.vault_bootstrap_secret,
    module.authentik_bootstrap_secret
  ]

  # Only show summary if any secrets were generated
  count = (module.vault_bootstrap_secret.generated || module.authentik_bootstrap_secret.generated) ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOF
      echo "Bootstrap secrets rotated. Commit and push to make Flux deploy them."
    EOF
  }
}
