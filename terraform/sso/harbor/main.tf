terraform {
  backend "kubernetes" {
    secret_suffix = "harbor-sso"
    namespace     = "flux-system"
  }
}

provider "authentik" {
  url   = var.authentik_url
  token = var.authentik_token
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
  client_secret      = var.client_secret
  authorization_flow = data.authentik_flow.default_authorization_flow.id

  redirect_uris = [
    "${var.harbor_url}/c/oidc/callback"
  ]

  property_mappings = [
    data.authentik_scope_mapping.openid.id,
    data.authentik_scope_mapping.email.id,
    data.authentik_scope_mapping.profile.id,
  ]

  signing_algorithm = "RS256"
}

# Data sources for default flows and mappings
data "authentik_flow" "default_authorization_flow" {
  slug = "default-authentication-flow"
}

data "authentik_scope_mapping" "openid" {
  scope_name = "openid"
}

data "authentik_scope_mapping" "email" {
  scope_name = "email"
}

data "authentik_scope_mapping" "profile" {
  scope_name = "profile"
}