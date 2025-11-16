# GITOPS MODULE VARIABLES

variable "kubeconfig" {
  description = "Kubeconfig from infrastructure module"
  type        = string
  sensitive   = true
}

variable "vault_address" {
  description = "Vault server address"
  type        = string
  default     = "http://vault.vault.svc.cluster.local:8200"
}

variable "authentik_url" {
  description = "Authentik server URL"
  type        = string
  default     = "https://authentik.test-cluster.agentydragon.com"
}

variable "authentik_token" {
  description = "Authentik API token"
  type        = string
  sensitive   = true
}

variable "cluster_domain" {
  description = "Domain name for cluster services"
  type        = string
}