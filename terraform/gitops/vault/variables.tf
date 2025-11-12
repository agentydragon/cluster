variable "vault_address" {
  description = "Vault server address"
  type        = string
  default     = "https://vault.test-cluster.agentydragon.com"
}

variable "kubernetes_api_url" {
  description = "Kubernetes API server URL (for Vault auth)"
  type        = string
  default     = "https://kubernetes.default.svc.cluster.local"
}

variable "kubeconfig_path" {
  description = "Path to kubeconfig file"
  type        = string
  default     = "/tmp/kubeconfig"
}
