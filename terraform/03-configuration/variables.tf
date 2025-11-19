# LAYER 3 VARIABLES - DNS zone management
# This layer only manages PowerDNS zones and records
# SSO configurations are managed separately via terraform/authentik-blueprint/ (tofu-controller)

variable "powerdns_api_key" {
  description = "PowerDNS API key for DNS management"
  type        = string
  sensitive   = true
}