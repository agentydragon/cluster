# Kagent SSO Configuration
# Creates Authentik proxy provider for Kagent UI authentication

# Data source for invalidation flow (required in provider ~> 2025.10.0)
data "authentik_flow" "default_invalidation" {
  slug = "default-provider-invalidation-flow"
}

resource "authentik_provider_proxy" "kagent" {
  name               = "kagent"
  external_host      = "https://kagent.test-cluster.agentydragon.com:8443"
  mode               = "forward_single"
  authorization_flow = data.authentik_flow.default_provider_authorization_implicit_consent.id
  invalidation_flow  = data.authentik_flow.default_invalidation.id

  # Forward auth doesn't need internal host or intercept headers
  access_token_validity = "hours=1"
}

resource "authentik_application" "kagent" {
  name              = "Kagent"
  slug              = "kagent"
  protocol_provider = authentik_provider_proxy.kagent.id
  meta_description  = "Kubernetes Agent Platform - AI agents with K8s integration"
  meta_launch_url   = "https://kagent.test-cluster.agentydragon.com:8443"
  open_in_new_tab   = true
}

resource "authentik_policy_binding" "kagent_access" {
  target = authentik_application.kagent.uuid
  group  = data.authentik_group.users.id
  order  = 0
}

# Note: No need to bind to embedded outpost - it automatically serves all proxy providers
