terraform {
  required_providers {
    authentik = {
      source  = "goauthentik/authentik"
      version = "~> 2025.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.36"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.5"
    }
  }
}