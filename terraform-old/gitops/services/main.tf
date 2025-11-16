# Version constraints inherited from /terraform/versions.tf

# Read secrets from Vault
data "vault_kv_secret_v2" "harbor_secrets" {
  mount = "kv"
  name  = "sso/harbor"
}

data "vault_kv_secret_v2" "gitea_secrets" {
  mount = "kv"
  name  = "sso/gitea"
}

data "vault_kv_secret_v2" "matrix_secrets" {
  mount = "kv"
  name  = "sso/matrix"
}

# Harbor OIDC Configuration (following ducktape pattern)
resource "authentik_provider_oauth2" "harbor" {
  count         = var.enable_harbor ? 1 : 0
  name          = "harbor-oidc"
  client_id     = "harbor"
  client_secret = data.vault_kv_secret_v2.harbor_secrets.data["client-secret"]

  authorization_flow = data.authentik_flow.default_authorization_flow.id
  invalidation_flow  = data.authentik_flow.default_invalidation_flow.id

  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "${var.harbor_external_url}/c/oidc/callback"
    },
    {
      matching_mode = "strict"
      url           = "${var.harbor_external_url}/c/oidc/login"
    }
  ]

  client_type = "confidential"
  issuer_mode = "per_provider"

  include_claims_in_id_token = true

  property_mappings = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.email.id,
    data.authentik_property_mapping_provider_scope.profile.id,
    data.authentik_property_mapping_provider_scope.groups.id,
    data.authentik_property_mapping_provider_scope.preferred_username.id,
  ]
}

resource "authentik_application" "harbor" {
  count             = var.enable_harbor ? 1 : 0
  name              = "Harbor Registry"
  slug              = "harbor"
  protocol_provider = authentik_provider_oauth2.harbor[0].id

  meta_launch_url  = var.harbor_external_url
  meta_description = "Private container registry with vulnerability scanning"

  policy_engine_mode = "any"
}

# Harbor OIDC configuration will be enabled once Harbor provider is configured
# resource "harbor_config_auth" "oidc" {
#   auth_mode = "oidc_auth"
#
#   oidc_name          = "Authentik"
#   oidc_endpoint      = "${var.authentik_external_url}/application/o/harbor/"
#   oidc_client_id     = authentik_provider_oauth2.harbor.client_id
#   oidc_client_secret = authentik_provider_oauth2.harbor.client_secret
#   oidc_groups_claim  = "groups"
#   oidc_admin_group   = "harbor-admins"
#   oidc_scope         = "openid,profile,email,groups"
#   oidc_user_claim    = "preferred_username"
#   oidc_verify_cert   = true
#   oidc_auto_onboard  = true
#
#   depends_on = [
#     authentik_provider_oauth2.harbor,
#     authentik_application.harbor
#   ]
# }

# Gitea OIDC Configuration
resource "authentik_provider_oauth2" "gitea" {
  count         = var.enable_gitea ? 1 : 0
  name          = "gitea-oidc"
  client_id     = "gitea"
  client_secret = data.vault_kv_secret_v2.gitea_secrets.data["client-secret"]

  authorization_flow = data.authentik_flow.default_authorization_flow.id
  invalidation_flow  = data.authentik_flow.default_invalidation_flow.id

  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "${var.gitea_external_url}/user/oauth2/authentik/callback"
    }
  ]

  client_type = "confidential"
  issuer_mode = "per_provider"

  include_claims_in_id_token = true

  property_mappings = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.email.id,
    data.authentik_property_mapping_provider_scope.profile.id,
    data.authentik_property_mapping_provider_scope.groups.id,
    data.authentik_property_mapping_provider_scope.preferred_username.id,
  ]
}

resource "authentik_application" "gitea" {
  count             = var.enable_gitea ? 1 : 0
  name              = "Gitea Git Service"
  slug              = "gitea"
  protocol_provider = authentik_provider_oauth2.gitea[0].id

  meta_launch_url  = var.gitea_external_url
  meta_description = "Git service with web interface"

  policy_engine_mode = "any"
}

# Gitea OIDC configuration will be enabled once Gitea provider is configured
# resource "gitea_oauth2_app" "authentik" {
#   name = "Authentik SSO"
#
#   client_id     = authentik_provider_oauth2.gitea.client_id
#   client_secret = authentik_provider_oauth2.gitea.client_secret
#
#   redirect_uris = [
#     "${var.gitea_external_url}/user/oauth2/authentik/callback"
#   ]
#
#   confidential_client = true
#
#   depends_on = [
#     authentik_provider_oauth2.gitea,
#     authentik_application.gitea
#   ]
# }

# Matrix OIDC Configuration (for future use)
resource "authentik_provider_oauth2" "matrix" {
  count         = var.enable_matrix ? 1 : 0
  name          = "matrix-oidc"
  client_id     = "matrix"
  client_secret = data.vault_kv_secret_v2.matrix_secrets.data["client-secret"]

  authorization_flow = data.authentik_flow.default_authorization_flow.id
  invalidation_flow  = data.authentik_flow.default_invalidation_flow.id

  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "${var.matrix_external_url}/_synapse/client/oidc/callback"
    }
  ]

  client_type = "confidential"
  issuer_mode = "per_provider"

  include_claims_in_id_token = true

  property_mappings = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.email.id,
    data.authentik_property_mapping_provider_scope.profile.id,
    data.authentik_property_mapping_provider_scope.groups.id,
    data.authentik_property_mapping_provider_scope.preferred_username.id,
  ]
}

resource "authentik_application" "matrix" {
  count             = var.enable_matrix ? 1 : 0
  name              = "Matrix Chat"
  slug              = "matrix"
  protocol_provider = authentik_provider_oauth2.matrix[0].id

  meta_launch_url  = var.matrix_external_url
  meta_description = "Decentralized chat and collaboration"

  policy_engine_mode = "any"
}

# Data sources for existing Authentik resources
data "authentik_flow" "default_authorization_flow" {
  slug = "default-provider-authorization-implicit-consent"
}

data "authentik_flow" "default_invalidation_flow" {
  slug = "default-provider-invalidation-flow"
}

data "authentik_property_mapping_provider_scope" "openid" {
  managed = "goauthentik.io/providers/oauth2/scope-openid"
}

data "authentik_property_mapping_provider_scope" "email" {
  managed = "goauthentik.io/providers/oauth2/scope-email"
}

data "authentik_property_mapping_provider_scope" "profile" {
  managed = "goauthentik.io/providers/oauth2/scope-profile"
}

data "authentik_property_mapping_provider_scope" "groups" {
  name = "Groups Mapping" # Custom mapping created in authentik module
}

data "authentik_property_mapping_provider_scope" "preferred_username" {
  name = "Preferred Username Mapping" # Custom mapping created in authentik module
}
