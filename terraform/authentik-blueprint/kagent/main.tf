terraform {
  required_version = ">= 1.0"

  required_providers {
    authentik = {
      source = "goauthentik/authentik"
    }
    restful = {
      source = "magodo/restful"
    }
  }

  backend "kubernetes" {
    secret_suffix = "authentik-blueprint-kagent"
    namespace     = "flux-system"
  }
}

provider "restful" {
  base_url = var.authentik_url
  security = {
    http = {
      token = {
        token = var.authentik_token
      }
    }
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

# Query the embedded outpost UUID dynamically
# For forward auth, we MUST use the embedded outpost because:
# - The ingress auth-url points to auth.test-cluster.agentydragon.com
# - That endpoint is served by the embedded outpost (part of main Authentik server)
# - Creating a separate outpost would require deploying it as a pod + updating ingress
data "http" "embedded_outpost" {
  url = "${var.authentik_url}/api/v3/outposts/instances/?name=${urlencode("authentik Embedded Outpost")}"

  request_headers = {
    Authorization = "Bearer ${var.authentik_token}"
    Accept        = "application/json"
  }

  depends_on = [authentik_provider_proxy.kagent]
}

locals {
  embedded_outpost_data = jsondecode(data.http.embedded_outpost.response_body)
  embedded_outpost_uuid = local.embedded_outpost_data.results[0].pk
}

# Assign Kagent provider to embedded outpost via API
# UUID is not stable (uuid4()), so we can't use static import
# Using restful provider for cleaner API interaction
resource "restful_operation" "assign_kagent_to_outpost" {
  path   = "/api/v3/outposts/instances/${local.embedded_outpost_uuid}/"
  method = "PATCH"
  body = jsonencode({
    providers = [authentik_provider_proxy.kagent.id]
  })
}
