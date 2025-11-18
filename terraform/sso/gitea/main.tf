terraform {
  backend "kubernetes" {
    secret_suffix = "gitea-sso"
    namespace     = "flux-system"
  }
}

provider "authentik" {
  url   = var.authentik_url
  token = var.authentik_token
}

# Create Authentik application for Gitea
resource "authentik_application" "gitea" {
  name              = "Gitea"
  slug              = "gitea"
  protocol_provider = authentik_provider_oauth2.gitea.id
  meta_description  = "Gitea Git Repository Management"
  meta_publisher    = "Gitea"
  open_in_new_tab   = true
}

# Create OAuth2 provider for Gitea
resource "authentik_provider_oauth2" "gitea" {
  name               = "gitea-oauth2"
  client_id          = "gitea"
  client_secret      = var.client_secret
  authorization_flow = data.authentik_flow.default_authorization_flow.id

  redirect_uris = [
    "${var.gitea_url}/user/oauth2/authentik/callback"
  ]

  property_mappings = data.authentik_property_mapping_provider_scope.scopes.ids

  signing_algorithm = "RS256"
}

# Data sources for default flows and mappings
data "authentik_flow" "default_authorization_flow" {
  slug = "default-authentication-flow"
}

data "authentik_property_mapping_provider_scope" "scopes" {
  managed_list = [
    "goauthentik.io/providers/oauth2/scope-openid",
    "goauthentik.io/providers/oauth2/scope-email",
    "goauthentik.io/providers/oauth2/scope-profile",
  ]
}