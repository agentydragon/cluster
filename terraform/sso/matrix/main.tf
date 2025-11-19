terraform {
  required_providers {
    authentik = {
      source = "goauthentik/authentik"
    }
  }

  backend "kubernetes" {
    secret_suffix = "matrix-sso"
    namespace     = "flux-system"
  }
}

provider "authentik" {
  url   = var.authentik_url
  token = var.authentik_token
}

# Create Authentik application for Matrix
resource "authentik_application" "matrix" {
  name              = "Matrix"
  slug              = "matrix"
  protocol_provider = authentik_provider_oauth2.matrix.id
  meta_description  = "Matrix Synapse Homeserver"
  meta_publisher    = "Matrix.org"
  open_in_new_tab   = true
}

# Create OAuth2 provider for Matrix
resource "authentik_provider_oauth2" "matrix" {
  name               = "matrix-oauth2"
  client_id          = "matrix"
  client_secret      = var.client_secret
  authorization_flow = data.authentik_flow.default_authorization_flow.id
  invalidation_flow  = data.authentik_flow.default_invalidation_flow.id

  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "${var.matrix_url}/_synapse/client/oidc/callback"
    }
  ]

  client_type                = "confidential"
  issuer_mode                = "per_provider"
  include_claims_in_id_token = true

  property_mappings = data.authentik_property_mapping_provider_scope.scopes.ids
}

# Data sources for default flows and mappings
data "authentik_flow" "default_authorization_flow" {
  slug = "default-authentication-flow"
}

data "authentik_flow" "default_invalidation_flow" {
  slug = "default-invalidation-flow"
}

data "authentik_property_mapping_provider_scope" "scopes" {
  managed_list = [
    "goauthentik.io/providers/oauth2/scope-openid",
    "goauthentik.io/providers/oauth2/scope-email",
    "goauthentik.io/providers/oauth2/scope-profile",
  ]
}