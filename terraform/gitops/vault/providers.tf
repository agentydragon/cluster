# Extract Vault root token from Kubernetes secret
data "kubernetes_secret" "vault_root_token" {
  metadata {
    name      = "vault-root-token"
    namespace = "vault"
  }
}

# Provider configurations
provider "vault" {
  address = var.vault_address
  token   = data.kubernetes_secret.vault_root_token.data["root-token"]
}

provider "kubernetes" {
  # Uses in-cluster authentication when running in tofu-controller
}
