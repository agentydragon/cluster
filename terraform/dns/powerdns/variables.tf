variable "powerdns_api_key" {
  description = "API key for PowerDNS authentication"
  type        = string
  sensitive   = true
}

variable "powerdns_server_url" {
  description = "URL for PowerDNS API endpoint"
  type        = string
  default     = "http://powerdns-api.dns-system:8081"
}

variable "cluster_domain" {
  description = "The domain name for the cluster zone"
  type        = string
  default     = "test-cluster.agentydragon.com"
}