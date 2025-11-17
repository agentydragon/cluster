variable "powerdns_api_key" {
  description = "PowerDNS API key"
  type        = string
  sensitive   = true
}

variable "powerdns_server_url" {
  description = "PowerDNS server URL"
  type        = string
  default     = "http://powerdns-api.dns-system:8081"
}

variable "cluster_domain" {
  description = "Cluster domain name"
  type        = string
  default     = "test-cluster.agentydragon.com"
}

variable "ingress_ip" {
  description = "Ingress controller IP address"
  type        = string
  default     = "10.0.3.2"
}