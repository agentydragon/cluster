terraform {
  required_version = ">= 1.0"

  required_providers {
    authentik = {
      source = "goauthentik/authentik"
    }
  }

  backend "kubernetes" {
    secret_suffix = "authentik-users"
    namespace     = "flux-system"
  }
}

provider "authentik" {
  url   = var.authentik_url
  token = var.authentik_token
}
