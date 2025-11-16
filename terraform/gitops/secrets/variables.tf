# Variables for secrets module
variable "vault_address" {
  description = "Vault server URL"
  type        = string
}

# kubeconfig_path variable removed - using in-cluster service account