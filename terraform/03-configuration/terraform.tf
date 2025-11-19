# LAYER 3: DNS Zone Management Provider Versions

terraform {
  required_version = ">= 1.0"

  backend "local" {
    path = "terraform.tfstate"
  }

  required_providers {
    # DNS management
    powerdns = {
      source  = "pan-net/powerdns"
      version = "~> 1.5.0"
    }
    # Secret storage (for PowerDNS API key)
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.4.0"
    }
    # API key generation
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7.0"
    }
  }
}
