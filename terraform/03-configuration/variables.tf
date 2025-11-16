# LAYER 3 VARIABLES - Service API configuration
# These variables are provided after services are deployed and ready

variable "powerdns_api_key" {
  description = "PowerDNS API key for DNS management"
  type        = string
  sensitive   = true
}

variable "authentik_token" {
  description = "Authentik API token for SSO configuration"
  type        = string
  sensitive   = true
}

variable "harbor_admin_password" {
  description = "Harbor admin password for registry configuration"
  type        = string
  sensitive   = true
}

variable "gitea_admin_token" {
  description = "Gitea admin token for git service configuration"
  type        = string
  sensitive   = true
}