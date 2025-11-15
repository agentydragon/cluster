# Provider configuration for secrets module

module "common" {
  source = "../modules/common"
  # Secrets module only needs Kubernetes provider
  vault_enabled = false
}

provider "kubernetes" {
  # Uses in-cluster authentication when running in tofu-controller
}