variable "vault_address" {
  description = "Vault server address"
  type        = string
  default     = "https://vault.test-cluster.agentydragon.com"
}

variable "kubeconfig_path" {
  description = "Path to kubeconfig file"
  type        = string
  default     = "/tmp/kubeconfig"
}
