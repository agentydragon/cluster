# Version constraints inherited from /terraform/versions.tf

# Enable KV secrets engine (if not already enabled)
resource "vault_mount" "kv" {
  path        = "kv"
  type        = "kv-v2"
  description = "SSO secrets storage"

  # Don't fail if mount already exists
  lifecycle {
    prevent_destroy = true
  }
}

# Enable Kubernetes auth method (for External Secrets Operator)
resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
  path = "kubernetes"

  lifecycle {
    prevent_destroy = true
  }
}

# Configure Kubernetes auth to use in-cluster service account
resource "vault_kubernetes_auth_backend_config" "cluster" {
  backend         = vault_auth_backend.kubernetes.path
  kubernetes_host = var.kubernetes_api_url

  # Use the cluster's CA certificate and default service account JWT
  kubernetes_ca_cert = file("/var/run/secrets/kubernetes.io/serviceaccount/ca.crt")
  token_reviewer_jwt = file("/var/run/secrets/kubernetes.io/serviceaccount/token")

  # Disable local CA verification (for dev clusters)
  disable_local_ca_jwt = false
}

# Create policy for External Secrets Operator
resource "vault_policy" "external_secrets" {
  name = "external-secrets"

  policy = <<EOF
# Allow reading SSO secrets
path "kv/data/sso/*" {
  capabilities = ["read"]
}

path "kv/metadata/sso/*" {
  capabilities = ["read", "list"]
}
EOF
}

# Create Kubernetes auth role for External Secrets Operator
resource "vault_kubernetes_auth_backend_role" "external_secrets" {
  backend   = vault_auth_backend.kubernetes.path
  role_name = "external-secrets"

  bound_service_account_names      = ["external-secrets"]
  bound_service_account_namespaces = ["external-secrets-system"]

  token_policies = [vault_policy.external_secrets.name]
  token_ttl      = 3600
  token_max_ttl  = 7200
}

# Create policy for Authentik service
resource "vault_policy" "authentik" {
  name = "authentik"

  policy = <<EOF
# Allow reading SSO secrets (for client secrets)
path "kv/data/sso/*" {
  capabilities = ["read"]
}

path "kv/metadata/sso/*" {
  capabilities = ["read", "list"]
}
EOF
}

# Create Kubernetes auth role for Authentik
resource "vault_kubernetes_auth_backend_role" "authentik" {
  backend   = vault_auth_backend.kubernetes.path
  role_name = "authentik"

  bound_service_account_names      = ["authentik"]
  bound_service_account_namespaces = ["authentik"]

  token_policies = [vault_policy.authentik.name]
  token_ttl      = 3600
  token_max_ttl  = 7200
}
