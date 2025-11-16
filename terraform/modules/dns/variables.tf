# DNS MODULE VARIABLES

variable "cluster_domain" {
  description = "Cluster domain name"
  type        = string
  default     = "test-cluster.agentydragon.com"
}

variable "cluster_vip" {
  description = "Cluster VIP for API endpoint DNS record"
  type        = string
}

variable "ingress_pool" {
  description = "Ingress pool IP for wildcard DNS record"
  type        = string
  default     = "10.0.3.2"
}

variable "powerdns_server_url" {
  description = "PowerDNS server API URL"
  type        = string
  default     = "http://powerdns.dns-system.svc.cluster.local:8081"
}

variable "powerdns_api_key" {
  description = "PowerDNS API key"
  type        = string
  sensitive   = true
}