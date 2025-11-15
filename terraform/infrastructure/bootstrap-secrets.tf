locals {
  cluster_root = "${path.module}/../.."
}

# Vault bootstrap secrets are now managed by Bank-Vaults operator
# module "vault_bootstrap_secret" removed - no longer needed

module "authentik_bootstrap_secret" {
  source = "./modules/bootstrap-secret"

  name         = "bootstrap"
  namespace    = "authentik"
  secret_key   = "bootstrap-token"
  service_name = "authentik"
  cluster_root = local.cluster_root

  depends_on = [null_resource.wait_for_sealed_secrets]
}

# Summary output
resource "null_resource" "bootstrap_summary" {
  depends_on = [
    module.authentik_bootstrap_secret
  ]

  # Only show summary if any secrets were generated
  count = module.authentik_bootstrap_secret.generated ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOF
      echo "Bootstrap secrets rotated. Commit and push to make Flux deploy them."
    EOF
  }
}
