terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.33.0"
    }
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

# Output for Kubernetes secret
output "powerdns_api_key" {
  value     = random_password.powerdns_api_key.result
  sensitive = true
}