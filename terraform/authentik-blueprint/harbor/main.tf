terraform {
  required_version = ">= 1.0"

  required_providers {
    authentik = {
      source = "goauthentik/authentik"
    }
    harbor = {
      source = "goharbor/harbor"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    vault = {
      source = "hashicorp/vault"
    }
  }

  backend "kubernetes" {
    secret_suffix = "authentik-blueprint-harbor"
    namespace     = "flux-system"
  }
}

provider "authentik" {
  url   = var.authentik_url
  token = var.authentik_token
}

provider "vault" {
  address         = var.vault_address
  token           = var.vault_token
  skip_tls_verify = true # Self-signed internal CA
}

# Create Authentik application for Harbor
resource "authentik_application" "harbor" {
  name              = "Harbor"
  slug              = "harbor"
  protocol_provider = authentik_provider_oauth2.harbor.id
  meta_description  = "Harbor Container Registry"
  meta_publisher    = "Harbor"
  open_in_new_tab   = true
}

# Create OAuth2 provider for Harbor
resource "authentik_provider_oauth2" "harbor" {
  name               = "harbor-oauth2"
  client_id          = "harbor"
  client_secret      = data.vault_kv_secret_v2.harbor_client_secret.data["harbor_client_secret"]
  authorization_flow = data.authentik_flow.default_authorization_flow.id
  invalidation_flow  = data.authentik_flow.default_invalidation_flow.id

  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "${var.harbor_url}/c/oidc/callback"
    }
  ]

  client_type                = "confidential"
  issuer_mode                = "per_provider"
  include_claims_in_id_token = true

  property_mappings = data.authentik_property_mapping_provider_scope.scopes.ids
}

# Read Harbor OAuth client secret from Vault
data "vault_kv_secret_v2" "harbor_client_secret" {
  mount = "kv"
  name  = "sso/client-secrets"
}

# Data sources for default flows and mappings
data "authentik_flow" "default_authorization_flow" {
  slug = "default-provider-authorization-implicit-consent"
}

data "authentik_flow" "default_invalidation_flow" {
  slug = "default-provider-invalidation-flow"
}

data "authentik_property_mapping_provider_scope" "scopes" {
  managed_list = [
    "goauthentik.io/providers/oauth2/scope-openid",
    "goauthentik.io/providers/oauth2/scope-email",
    "goauthentik.io/providers/oauth2/scope-profile",
  ]
}