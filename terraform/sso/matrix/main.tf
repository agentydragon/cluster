terraform {
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
  protocol_provider = authentik_provider_saml.matrix.id
  meta_description  = "Matrix Synapse Homeserver"
  meta_publisher    = "Matrix.org"
  open_in_new_tab   = true
}

# Create SAML provider for Matrix
resource "authentik_provider_saml" "matrix" {
  name               = "matrix-saml"
  authorization_flow = data.authentik_flow.default_authorization_flow.id

  acs_url    = "${var.matrix_url}/_synapse/client/saml2/authn_response"
  issuer     = "https://auth.test-cluster.agentydragon.com"
  sp_binding = "post"

  property_mappings = [
    data.authentik_property_mapping_saml.email.id,
    data.authentik_property_mapping_saml.name.id,
    data.authentik_property_mapping_saml.username.id,
  ]

  signing_algorithm = "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"
  digest_algorithm  = "http://www.w3.org/2001/04/xmlenc#sha256"

  # Use client secret for SAML signing key if needed
  # Currently not used but kept for future SAML configuration
  # client_secret = var.client_secret
}

# Data sources for default flows and mappings
data "authentik_flow" "default_authorization_flow" {
  slug = "default-authentication-flow"
}

data "authentik_property_mapping_saml" "email" {
  name = "authentik default SAML Mapping: Email"
}

data "authentik_property_mapping_saml" "name" {
  name = "authentik default SAML Mapping: Name"
}

data "authentik_property_mapping_saml" "username" {
  name = "authentik default SAML Mapping: Username"
}