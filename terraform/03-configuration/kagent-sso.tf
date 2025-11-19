# Kagent SSO Configuration
# Creates Authentik proxy provider for Kagent UI authentication

resource "authentik_provider_proxy" "kagent" {
  name               = "kagent"
  external_host      = "https://kagent.test-cluster.agentydragon.com:8443"
  mode               = "forward_single"
  authorization_flow = data.authentik_flow.default_provider_authorization_implicit_consent.id

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

# Assign to Proxy Outpost
resource "authentik_outpost_binding" "kagent" {
  outpost = data.authentik_outpost.embedded.id
  target  = authentik_provider_proxy.kagent.id
}
