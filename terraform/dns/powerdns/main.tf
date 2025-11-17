terraform {
  backend "kubernetes" {
    secret_suffix = "powerdns-config"
    namespace     = "flux-system"
  }
}

provider "powerdns" {
  api_key    = var.powerdns_api_key
  server_url = var.powerdns_server_url
}

# Create the main zone for the cluster
resource "powerdns_zone" "cluster_zone" {
  name        = var.cluster_domain
  kind        = "Master"
  nameservers = ["ns1.${var.cluster_domain}"]
}

# NS record pointing to itself
resource "powerdns_record" "ns1" {
  zone    = powerdns_zone.cluster_zone.name
  name    = "ns1.${var.cluster_domain}"
  type    = "A"
  ttl     = 300
  records = [var.ingress_ip]
}

# Wildcard record for all subdomains to ingress
resource "powerdns_record" "wildcard" {
  zone    = powerdns_zone.cluster_zone.name
  name    = "*.${var.cluster_domain}"
  type    = "A"
  ttl     = 300
  records = [var.ingress_ip]
}

# Specific records for key services
resource "powerdns_record" "git" {
  zone    = powerdns_zone.cluster_zone.name
  name    = "git.${var.cluster_domain}"
  type    = "A"
  ttl     = 300
  records = [var.ingress_ip]
}

resource "powerdns_record" "registry" {
  zone    = powerdns_zone.cluster_zone.name
  name    = "registry.${var.cluster_domain}"
  type    = "A"
  ttl     = 300
  records = [var.ingress_ip]
}

resource "powerdns_record" "auth" {
  zone    = powerdns_zone.cluster_zone.name
  name    = "auth.${var.cluster_domain}"
  type    = "A"
  ttl     = 300
  records = [var.ingress_ip]
}