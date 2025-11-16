# Version constraints inherited from /terraform/versions.tf

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

# Generate service admin passwords
resource "random_password" "harbor_admin_password" {
  length  = 32
  special = true

  lifecycle {
    ignore_changes = [length, special]
  }
}

resource "random_password" "gitea_admin_password" {
  length  = 32
  special = true

  lifecycle {
    ignore_changes = [length, special]
  }
}

# Store all SSO secrets in Vault (following ducktape pattern)
resource "vault_kv_secret_v2" "harbor_secrets" {
  mount = "kv"
  name  = "sso/harbor"

  cas = 0 # Only create if it doesn't exist

  data_json = jsonencode({
    client-secret  = random_password.harbor_client_secret.result
    admin-password = random_password.harbor_admin_password.result
    managed-by     = "terraform-sso"
    created-at     = timestamp()
  })

  lifecycle {
    ignore_changes = [cas, data_json]
  }
}

resource "vault_kv_secret_v2" "gitea_secrets" {
  mount = "kv"
  name  = "sso/gitea"

  cas = 0

  data_json = jsonencode({
    client-secret  = random_password.gitea_client_secret.result
    admin-password = random_password.gitea_admin_password.result
    managed-by     = "terraform-sso"
    created-at     = timestamp()
  })

  lifecycle {
    ignore_changes = [cas, data_json]
  }
}

resource "vault_kv_secret_v2" "matrix_secrets" {
  mount = "kv"
  name  = "sso/matrix"

  cas = 0

  data_json = jsonencode({
    client-secret = random_password.matrix_client_secret.result
    managed-by    = "terraform-sso"
    created-at    = timestamp()
  })

  lifecycle {
    ignore_changes = [cas, data_json]
  }
}

# Note: Authentik bootstrap token is managed directly in HelmRelease
# (chicken-and-egg problem - need Authentik running to store its secrets in Vault)
