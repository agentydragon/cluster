variable "authentik_url" {
  description = "Authentik API URL"
  type        = string
  default     = "https://auth.test-cluster.agentydragon.com"
}

variable "authentik_external_url" {
  description = "External URL for Authentik (user-facing)"
  type        = string
  default     = "https://auth.test-cluster.agentydragon.com"
}

variable "harbor_url" {
  description = "Harbor API URL"
  type        = string
  default     = "https://registry.test-cluster.agentydragon.com"
}

variable "harbor_external_url" {
  description = "External URL for Harbor (user-facing)"
  type        = string
  default     = "https://registry.test-cluster.agentydragon.com"
}

variable "harbor_username" {
  description = "Harbor admin username"
  type        = string
  default     = "admin"
}

variable "gitea_url" {
  description = "Gitea API URL"
  type        = string
  default     = "https://git.test-cluster.agentydragon.com"
}

variable "gitea_external_url" {
  description = "External URL for Gitea (user-facing)"
  type        = string
  default     = "https://git.test-cluster.agentydragon.com"
}

variable "matrix_external_url" {
  description = "External URL for Matrix (user-facing)"
  type        = string
  default     = "https://matrix.test-cluster.agentydragon.com"
}

# vault_address and kubeconfig_path moved to shared module
# Uses defaults from ../modules/providers/variables.tf
