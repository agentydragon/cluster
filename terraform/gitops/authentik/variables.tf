# Variables for authentik module

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