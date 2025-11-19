terraform {
  required_providers {
    vault = {
      source = "hashicorp/vault"
    }
  }

  backend "kubernetes" {
    secret_suffix = "vault-config"
    namespace     = "flux-system"
  }
}

provider "vault" {
  address = var.vault_address
}

# Enable OIDC auth method
resource "vault_jwt_auth_backend" "oidc" {
  path               = "oidc"
  type               = "oidc"
  description        = "OIDC authentication with Authentik"
  oidc_discovery_url = var.authentik_oidc_discovery_url
  oidc_client_id     = "vault"
  oidc_client_secret = var.vault_client_secret
  default_role       = "authentik-users"

  tune {
    listing_visibility = "unauth"
    default_lease_ttl  = "1h"
    max_lease_ttl      = "24h"
  }
}

# Create OIDC role for Authentik users
resource "vault_jwt_auth_backend_role" "authentik_users" {
  backend   = vault_jwt_auth_backend.oidc.path
  role_name = "authentik-users"
  role_type = "oidc"

  bound_audiences = ["vault"]
  user_claim      = "email"
  groups_claim    = "groups"

  allowed_redirect_uris = [
    "${var.vault_external_url}/ui/vault/auth/oidc/oidc/callback",
    "${var.vault_external_url}/oidc/callback",
  ]

  oidc_scopes = ["openid", "email", "profile"]

  token_ttl               = 3600  # 1 hour
  token_max_ttl           = 86400 # 24 hours
  token_policies          = ["default"]
  token_bound_cidrs       = []
  token_explicit_max_ttl  = 0
  token_no_default_policy = false
  token_num_uses          = 0
  token_period            = 0
  token_type              = "default"
}