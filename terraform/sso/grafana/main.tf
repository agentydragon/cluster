terraform {
  required_providers {
    authentik = {
      source = "goauthentik/authentik"
    }
  }

  backend "kubernetes" {
    secret_suffix = "grafana-sso"
    namespace     = "flux-system"
  }
}

provider "authentik" {
  url   = var.authentik_url
  token = var.authentik_token
}

# Create Authentik application for Grafana
resource "authentik_application" "grafana" {
  name              = "Grafana"
  slug              = "grafana"
  protocol_provider = authentik_provider_oauth2.grafana.id
  meta_description  = "Grafana Monitoring and Observability"
  meta_publisher    = "Grafana Labs"
  open_in_new_tab   = true
}

# Create OAuth2 provider for Grafana
resource "authentik_provider_oauth2" "grafana" {
  name               = "grafana-oauth2"
  client_id          = "grafana"
  client_secret      = var.client_secret
  authorization_flow = data.authentik_flow.default_authorization_flow.id
  invalidation_flow  = data.authentik_flow.default_invalidation_flow.id

  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "${var.grafana_url}/login/generic_oauth"
    }
  ]

  client_type                = "confidential"
  issuer_mode                = "per_provider"
  include_claims_in_id_token = true

  property_mappings = data.authentik_property_mapping_provider_scope.scopes.ids
}

# Data sources for default flows and mappings
data "authentik_flow" "default_authorization_flow" {
  slug = "default-authorization-flow"
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
