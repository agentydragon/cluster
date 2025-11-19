# HARBOR OIDC CONFIGURATION
# Configure Harbor container registry with Authentik OIDC authentication
# This runs via tofu-controller after Harbor is deployed
# Reference: docs/HARBOR_SSO_AUTOMATION.md

# Provider versions are centralized in root terraform.tf

provider "kubernetes" {
  config_path = "~/.kube/config"
}

# Data source: Harbor OAuth client secret (ESO-generated, reflected to flux-system)
data "kubernetes_secret" "harbor_oauth_client_secret" {
  metadata {
    name      = "harbor-oauth-client-secret"
    namespace = "flux-system"
  }
}

# Data source: Harbor admin password from Vault (SSOT)
data "vault_kv_secret_v2" "harbor_admin_password" {
  mount = "kv"
  name  = "harbor/admin"
}

provider "harbor" {
  url      = var.harbor_url
  username = "admin"
  password = data.vault_kv_secret_v2.harbor_admin_password.data["password"]
}

# Configure Harbor OIDC authentication with Authentik
resource "harbor_config_auth" "oidc" {
  # Set authentication mode to OIDC
  auth_mode = "oidc_auth"

  # OIDC provider configuration
  oidc_name          = "Authentik"
  oidc_endpoint      = "${var.authentik_url}/application/o/harbor/"
  oidc_client_id     = "harbor"
  oidc_client_secret = data.kubernetes_secret.harbor_oauth_client_secret.data["client_secret"]
  oidc_scope         = "openid,email,profile"
  oidc_verify_cert   = true

  # Auto-create users on first OIDC login
  oidc_auto_onboard = true

  # Username claim from OIDC token
  oidc_user_claim = "preferred_username"

  # Group mapping configuration
  oidc_groups_claim = "groups"
  oidc_admin_group  = "harbor-admins"
}
