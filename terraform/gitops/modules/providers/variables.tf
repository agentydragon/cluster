# Variables for providers module

variable "vault_enabled" {
  description = "Whether to enable Vault data sources"
  type        = bool
  default     = false
}

# Shared provider URLs - passed from calling modules
variable "vault_address" {
  description = "Vault server address"
  type        = string
  default     = "https://vault.test-cluster.agentydragon.com"
}

variable "authentik_url" {
  description = "Authentik server URL"
  type        = string
  default     = "https://auth.test-cluster.agentydragon.com"
}