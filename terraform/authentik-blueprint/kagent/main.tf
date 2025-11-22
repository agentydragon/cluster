terraform {
  required_version = ">= 1.0"

  required_providers {
    authentik = {
      source = "goauthentik/authentik"
    }
    http = {
      source = "hashicorp/http"
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

data "authentik_group" "admins" {
  name = "authentik Admins"
}

# Kagent Proxy Provider for Forward Auth
resource "authentik_provider_proxy" "kagent" {
  name               = "kagent"
  external_host      = var.kagent_url
  mode               = "forward_single"
  authorization_flow = data.authentik_flow.default_authorization_flow.id
  invalidation_flow  = data.authentik_flow.default_invalidation.id

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

# Query embedded outpost UUID dynamically
data "http" "embedded_outpost" {
  url = "${var.authentik_url}/api/v3/outposts/instances/?managed=goauthentik.io%2Foutposts%2Fembedded"
  request_headers = {
    Authorization = "Bearer ${var.authentik_token}"
    Accept        = "application/json"
  }
}

locals {
  embedded_outpost_id = try(jsondecode(data.http.embedded_outpost.response_body).results[0].pk, null)
}

# Import and manage the embedded outpost to assign kagent provider
resource "authentik_outpost" "embedded" {
  name = "authentik Embedded Outpost"
  type = "proxy"
  protocol_providers = [
    authentik_provider_proxy.kagent.id
  ]
}

# Import block to import the existing embedded outpost
import {
  to = authentik_outpost.embedded
  id = local.embedded_outpost_id
}
