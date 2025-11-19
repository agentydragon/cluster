variable "authentik_url" {
  description = "Authentik server URL"
  type        = string
  # No default - must be provided by caller
}

variable "authentik_token" {
  description = "Authentik API token"
  type        = string
  sensitive   = true
}

variable "client_secret" {
  description = "OAuth2 client secret for Matrix"
  type        = string
  sensitive   = true
}

variable "matrix_url" {
  description = "Matrix server URL"
  type        = string
  default     = "https://matrix.test-cluster.agentydragon.com"
}

