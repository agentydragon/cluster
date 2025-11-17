terraform {
  backend "kubernetes" {
    secret_suffix = "powerdns-secrets"
    namespace     = "flux-system"
  }
}

# Generate secure PowerDNS API key
resource "random_password" "powerdns_api_key" {
  length  = 32
  special = false

  lifecycle {
    ignore_changes = [length, special]
  }
}

# Create Kubernetes secret with API key for PowerDNS container
resource "kubernetes_secret" "powerdns_api_key" {
  metadata {
    name      = "powerdns-api-key"
    namespace = "flux-system"
  }

  data = {
    powerdns_api_key = random_password.powerdns_api_key.result
  }

  type = "Opaque"
}