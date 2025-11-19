terraform {
  required_providers {
    vault = {
      source = "hashicorp/vault"
    }
    random = {
      source = "hashicorp/random"
    }
  }

  backend "kubernetes" {
    secret_suffix = "sso-secrets"
    namespace     = "flux-system"
  }
}

provider "vault" {
  address = var.vault_address
  token   = var.vault_token
}

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

resource "random_password" "vault_client_secret" {
  length  = 32
  special = false

  lifecycle {
    ignore_changes = [length, special]
  }
}

# Generate Authentik API/Bootstrap token (single token for both bootstrap and API access)
resource "random_password" "authentik_api_token" {
  length  = 64
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
    vault_client_secret  = random_password.vault_client_secret.result
    authentik_api_token  = random_password.authentik_api_token.result
  })

  # Temporarily commented to allow adding authentik_api_token to existing secret
  # lifecycle {
  #   ignore_changes = [data_json]
  # }
}