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
