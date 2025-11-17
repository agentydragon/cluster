variable "authentik_url" {
  description = "Authentik server URL"
  type        = string
  default     = "https://auth.test-cluster.agentydragon.com"
}

variable "authentik_token" {
  description = "Authentik API token"
  type        = string
  sensitive   = true
}

variable "gitea_url" {
  description = "Gitea server URL"
  type        = string
  default     = "https://git.test-cluster.agentydragon.com"
}

variable "client_secret" {
  description = "OAuth2 client secret for Gitea"
  type        = string
  sensitive   = true
}