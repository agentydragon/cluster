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

variable "vault_address" {
  description = "Vault server URL"
  type        = string
  default     = "https://vault.test-cluster.agentydragon.com"
}

# kubeconfig_path variable removed - using in-cluster service account

# Enable/disable individual services
variable "enable_harbor" {
  description = "Enable Harbor OIDC configuration"
  type        = bool
  default     = false
}

variable "enable_gitea" {
  description = "Enable Gitea OIDC configuration"
  type        = bool
  default     = false
}

variable "enable_matrix" {
  description = "Enable Matrix OIDC configuration"
  type        = bool
  default     = false
}
