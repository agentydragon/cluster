variable "authentik_url" {
  description = "Authentik server URL"
  type        = string
}

variable "authentik_token" {
  description = "Authentik API token"
  type        = string
  sensitive   = true
}

variable "vault_url" {
  description = "Vault server URL"
  type        = string
  default     = "https://vault.test-cluster.agentydragon.com"
}

variable "client_secret" {
  description = "OAuth2 client secret for Vault"
  type        = string
  sensitive   = true
}
