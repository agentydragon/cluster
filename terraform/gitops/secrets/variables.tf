# Variables for secrets module
variable "vault_address" {
  description = "Vault server URL"
  type        = string
}

variable "kubeconfig_path" {
  description = "Path to kubeconfig file"
  type        = string
  default     = "/tmp/kubeconfig"
}