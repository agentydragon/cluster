terraform {
  backend "kubernetes" {
    secret_suffix = "authentik-flows"
    namespace     = "flux-system"
  }
}

provider "authentik" {
  url   = var.authentik_url
  token = var.authentik_token
}

# Create default authentication flow
resource "authentik_flow" "default_authentication" {
  name               = "Welcome to authentik!"
  slug               = "default-authentication-flow"
  title              = "Welcome to authentik!"
  designation        = "authentication"
  policy_engine_mode = "any"
  compatibility_mode = true
}

# Create stages for authentication flow
resource "authentik_stage_identification" "default_authentication_identification" {
  name           = "default-authentication-identification"
  user_fields    = ["username", "email"]
  password_stage = authentik_stage_password.default_authentication_password.id
}

resource "authentik_stage_password" "default_authentication_password" {
  name     = "default-authentication-password"
  backends = ["authentik.core.auth.InbuiltBackend"]
}

resource "authentik_stage_user_login" "default_authentication_login" {
  name = "default-authentication-login"
}

# Bind stages to authentication flow
resource "authentik_flow_stage_binding" "default_authentication_identification_binding" {
  target = authentik_flow.default_authentication.uuid
  stage  = authentik_stage_identification.default_authentication_identification.id
  order  = 10
}

resource "authentik_flow_stage_binding" "default_authentication_password_binding" {
  target = authentik_flow.default_authentication.uuid
  stage  = authentik_stage_password.default_authentication_password.id
  order  = 20
}

resource "authentik_flow_stage_binding" "default_authentication_login_binding" {
  target = authentik_flow.default_authentication.uuid
  stage  = authentik_stage_user_login.default_authentication_login.id
  order  = 30
}

# Create default authorization flow (implicit consent)
resource "authentik_flow" "default_authorization" {
  name               = "Authorize Application"
  slug               = "default-authorization-flow"
  title              = "Redirecting to %(app)s"
  designation        = "authorization"
  policy_engine_mode = "any"
  compatibility_mode = true
}

# Create consent stage for authorization
resource "authentik_stage_consent" "default_authorization_consent" {
  name = "default-authorization-consent"
  mode = "always_require"
}

# Bind consent stage to authorization flow
resource "authentik_flow_stage_binding" "default_authorization_consent_binding" {
  target = authentik_flow.default_authorization.uuid
  stage  = authentik_stage_consent.default_authorization_consent.id
  order  = 10
}

# Create default invalidation flow (logout)
resource "authentik_flow" "default_invalidation" {
  name               = "Default Invalidation Flow"
  slug               = "default-invalidation-flow"
  title              = "Logout"
  designation        = "invalidation"
  policy_engine_mode = "any"
  compatibility_mode = true
}

# Create user logout stage
resource "authentik_stage_user_logout" "default_invalidation_logout" {
  name = "default-invalidation-logout"
}

# Bind logout stage to invalidation flow
resource "authentik_flow_stage_binding" "default_invalidation_logout_binding" {
  target = authentik_flow.default_invalidation.uuid
  stage  = authentik_stage_user_logout.default_invalidation_logout.id
  order  = 10
}

# Outputs for other modules to reference
output "default_authentication_flow_id" {
  description = "UUID of the default authentication flow"
  value       = authentik_flow.default_authentication.uuid
}

output "default_authorization_flow_id" {
  description = "UUID of the default authorization flow"
  value       = authentik_flow.default_authorization.uuid
}

output "default_invalidation_flow_id" {
  description = "UUID of the default invalidation flow"
  value       = authentik_flow.default_invalidation.uuid
}
