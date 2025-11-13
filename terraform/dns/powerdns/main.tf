terraform {
  required_providers {
    powerdns = {
      source  = "pan-net/powerdns"
      version = "~> 1.5.0"
    }
  }
}

# Configure PowerDNS provider to use in-cluster API
provider "powerdns" {
  api_key    = var.powerdns_api_key
  server_url = var.powerdns_server_url
}

# Create the main zone for the cluster
resource "powerdns_zone" "cluster_zone" {
  name        = var.cluster_domain
  kind        = "Master"
  nameservers = ["ns1.${var.cluster_domain}"]

  # Basic SOA record
  soa_edit_api = "DEFAULT"
}

# NS record pointing to this PowerDNS instance
resource "powerdns_record" "ns_record" {
  zone    = powerdns_zone.cluster_zone.name
  name    = "ns1.${var.cluster_domain}"
  type    = "A"
  ttl     = 300
  records = ["10.0.3.3"] # PowerDNS LoadBalancer IP
}

# Example records for cluster services
resource "powerdns_record" "wildcard_record" {
  zone    = powerdns_zone.cluster_zone.name
  name    = "*.${var.cluster_domain}"
  type    = "A"
  ttl     = 300
  records = ["10.0.3.2"] # Ingress LoadBalancer IP
}