variable "authentik_url" {
  description = "Authentik server URL"
  type        = string
  default     = "http://authentik-server.authentik.svc.cluster.local"
}

variable "authentik_token" {
  description = "Authentik API token"
  type        = string
  sensitive   = true
}

variable "harbor_url" {
  description = "Harbor server URL"
  type        = string
  default     = "https://harbor.test-cluster.agentydragon.com"
}

variable "client_secret" {
  description = "OAuth2 client secret for Harbor"
  type        = string
  sensitive   = true
}