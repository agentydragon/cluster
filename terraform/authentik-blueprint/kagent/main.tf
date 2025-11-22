terraform {
  required_version = ">= 1.0"

  required_providers {
    authentik = {
      source = "goauthentik/authentik"
    }
    http = {
      source = "hashicorp/http"
    }
    null = {
      source = "hashicorp/null"
    }
  }

  backend "kubernetes" {
    secret_suffix = "authentik-blueprint-kagent"
    namespace     = "flux-system"
  }
}

provider "authentik" {
  url   = var.authentik_url
  token = var.authentik_token
}

# Data source for invalidation flow (required in provider ~> 2025.10.0)
data "authentik_flow" "default_invalidation" {
  slug = "default-provider-invalidation-flow"
}

data "authentik_flow" "default_authorization_flow" {
  slug = "default-provider-authorization-implicit-consent"
}

data "authentik_flow" "default_authentication" {
  slug = "default-authentication-flow"
}

data "authentik_group" "admins" {
  name = "authentik Admins"
}

# Kagent Proxy Provider for Forward Auth
resource "authentik_provider_proxy" "kagent" {
  name                = "kagent"
  external_host       = var.kagent_url
  mode                = "forward_single"
  authentication_flow = data.authentik_flow.default_authentication.id
  authorization_flow  = data.authentik_flow.default_authorization_flow.id
  invalidation_flow   = data.authentik_flow.default_invalidation.id

  # Forward auth doesn't need internal host
  access_token_validity = "hours=1"
}

# Kagent Application
resource "authentik_application" "kagent" {
  name              = "Kagent"
  slug              = "kagent"
  protocol_provider = authentik_provider_proxy.kagent.id
  meta_description  = "Kubernetes Agent Platform - AI agents with K8s integration"
  meta_launch_url   = var.kagent_url
  open_in_new_tab   = true
}

# Policy Binding - Allow admins group
resource "authentik_policy_binding" "kagent_access" {
  target = authentik_application.kagent.uuid
  group  = data.authentik_group.admins.id
  order  = 0
}

# Note: The Kagent proxy provider must be manually assigned to the embedded outpost
# This can be done via the Authentik admin UI: Admin Interface -> Outposts -> authentik Embedded Outpost
# Or via API:
#   curl -X PATCH "https://auth.test-cluster.agentydragon.com/api/v3/outposts/instances/<outpost-id>/" \
#     -H "Content-Type: application/json" -H "Authorization: Bearer <token>" \
#     -d '{"providers":[<provider-id>]}'
