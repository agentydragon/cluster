terraform {
  required_providers {
    authentik = {
      source = "goauthentik/authentik"
    }
    vault = {
      source = "hashicorp/vault"
    }
    harbor = {
      source = "goharbor/harbor"
    }
    gitea = {
      source = "go-gitea/gitea"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}

# GITOPS MODULE: SSO, secrets management, and application services
# Manages Vault, Authentik, Harbor, Gitea, Matrix with proper SSO integration

# Generate secure client secrets for all SSO services
resource "random_password" "harbor_client_secret" {
  length  = 32
  special = false

  lifecycle {
    ignore_changes = [length, special]
  }
}

resource "random_password" "gitea_client_secret" {
  length  = 32
  special = false

  lifecycle {
    ignore_changes = [length, special]
  }
}

resource "random_password" "matrix_client_secret" {
  length  = 32
  special = false

  lifecycle {
    ignore_changes = [length, special]
  }
}

# Store all SSO client secrets in Vault for retrieval by applications
resource "vault_generic_secret" "sso_client_secrets" {
  path = "kv/sso/client-secrets"

  data_json = jsonencode({
    harbor_client_secret = random_password.harbor_client_secret.result
    gitea_client_secret  = random_password.gitea_client_secret.result
    matrix_client_secret = random_password.matrix_client_secret.result
  })

  lifecycle {
    ignore_changes = [data_json]
  }
}

# Create admin groups for each service in Authentik
resource "authentik_group" "harbor_admins" {
  name = "harbor-admins"
}

resource "authentik_group" "gitea_admins" {
  name = "gitea-admins"
}

resource "authentik_group" "matrix_admins" {
  name = "matrix-admins"
}

# Create custom property mappings for OIDC
resource "authentik_property_mapping_provider_scope" "groups" {
  name        = "Groups Mapping"
  scope_name  = "groups"
  description = "Groups scope for SSO services"
  expression  = "return {'groups': [group.name for group in user.ak_groups.all()]}"
}

resource "authentik_property_mapping_provider_scope" "preferred_username" {
  name        = "Preferred Username Mapping"
  scope_name  = "openid"
  description = "Preferred username mapping for SSO services"
  expression  = "return {'preferred_username': request.user.username}"
}

# Create automation user with access to all admin groups
resource "authentik_user" "automation" {
  username = "automation"
  name     = "SSO Automation User"
  email    = "automation@test-cluster.agentydragon.com"

  # Add to all admin groups
  groups = [
    authentik_group.harbor_admins.id,
    authentik_group.gitea_admins.id,
    authentik_group.matrix_admins.id
  ]

  is_active = true
}

# Data sources for Authentik default flows and property mappings
data "authentik_flow" "default_authorization_flow" {
  slug = "default-authorization-flow"
}

data "authentik_flow" "default_invalidation_flow" {
  slug = "default-invalidation-flow"
}

# Default property mappings
data "authentik_property_mapping_provider_scope" "openid" {
  name = "authentik default OAuth Mapping: OpenID 'openid'"
}

data "authentik_property_mapping_provider_scope" "email" {
  name = "authentik default OAuth Mapping: OpenID 'email'"
}

data "authentik_property_mapping_provider_scope" "profile" {
  name = "authentik default OAuth Mapping: OpenID 'profile'"
}

# HARBOR OIDC PROVIDER
resource "authentik_provider_oauth2" "harbor" {
  name          = "harbor-oidc"
  client_id     = "harbor"
  client_secret = random_password.harbor_client_secret.result

  authorization_flow = data.authentik_flow.default_authorization_flow.id
  invalidation_flow  = data.authentik_flow.default_invalidation_flow.id

  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "https://harbor.${var.cluster_domain}/c/oidc/callback"
    },
    {
      matching_mode = "strict"
      url           = "https://harbor.${var.cluster_domain}/c/oidc/login"
    }
  ]

  client_type = "confidential"
  issuer_mode = "per_provider"

  include_claims_in_id_token = true

  property_mappings = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.email.id,
    data.authentik_property_mapping_provider_scope.profile.id,
    authentik_property_mapping_provider_scope.groups.id,
    authentik_property_mapping_provider_scope.preferred_username.id,
  ]
}

resource "authentik_application" "harbor" {
  name              = "Harbor Registry"
  slug              = "harbor"
  protocol_provider = authentik_provider_oauth2.harbor.id

  meta_launch_url  = "https://harbor.${var.cluster_domain}"
  meta_description = "Private container registry with vulnerability scanning"

  policy_engine_mode = "any"
}

# GITEA OIDC PROVIDER
resource "authentik_provider_oauth2" "gitea" {
  name          = "gitea-oidc"
  client_id     = "gitea"
  client_secret = random_password.gitea_client_secret.result

  authorization_flow = data.authentik_flow.default_authorization_flow.id
  invalidation_flow  = data.authentik_flow.default_invalidation_flow.id

  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "https://gitea.${var.cluster_domain}/user/oauth2/authentik/callback"
    }
  ]

  client_type = "confidential"
  issuer_mode = "per_provider"

  include_claims_in_id_token = true

  property_mappings = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.email.id,
    data.authentik_property_mapping_provider_scope.profile.id,
    authentik_property_mapping_provider_scope.groups.id,
    authentik_property_mapping_provider_scope.preferred_username.id,
  ]
}

resource "authentik_application" "gitea" {
  name              = "Gitea"
  slug              = "gitea"
  protocol_provider = authentik_provider_oauth2.gitea.id

  meta_launch_url  = "https://gitea.${var.cluster_domain}"
  meta_description = "Git repository hosting and collaboration"

  policy_engine_mode = "any"
}

# MATRIX OIDC PROVIDER
resource "authentik_provider_oauth2" "matrix" {
  name          = "matrix-oidc"
  client_id     = "matrix"
  client_secret = random_password.matrix_client_secret.result

  authorization_flow = data.authentik_flow.default_authorization_flow.id
  invalidation_flow  = data.authentik_flow.default_invalidation_flow.id

  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "https://matrix.${var.cluster_domain}/_synapse/client/oidc/callback"
    }
  ]

  client_type = "confidential"
  issuer_mode = "per_provider"

  include_claims_in_id_token = true

  property_mappings = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.email.id,
    data.authentik_property_mapping_provider_scope.profile.id,
    authentik_property_mapping_provider_scope.groups.id,
    authentik_property_mapping_provider_scope.preferred_username.id,
  ]
}

resource "authentik_application" "matrix" {
  name              = "Matrix"
  slug              = "matrix"
  protocol_provider = authentik_provider_oauth2.matrix.id

  meta_launch_url  = "https://matrix.${var.cluster_domain}"
  meta_description = "Secure, decentralized communication"

  policy_engine_mode = "any"
}