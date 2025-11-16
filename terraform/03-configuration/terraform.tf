# LAYER 3: Configuration Provider Versions

terraform {
  required_version = ">= 1.0"

  backend "local" {
    path = "terraform.tfstate"
  }

  required_providers {
    # Service API providers
    powerdns = {
      source  = "pan-net/powerdns"
      version = "~> 1.5.0"
    }
    authentik = {
      source  = "goauthentik/authentik"
      version = "~> 2025.10.0"
    }
    harbor = {
      source  = "goharbor/harbor"
      version = "~> 3.11.0"
    }
    gitea = {
      source  = "go-gitea/gitea"
      version = "~> 0.7.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7.0"
    }
  }
}