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

variable "matrix_url" {
  description = "Matrix server URL"
  type        = string
  default     = "https://matrix.test-cluster.agentydragon.com"
}

