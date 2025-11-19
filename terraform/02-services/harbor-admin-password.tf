# HARBOR ADMIN PASSWORD
# Store in Vault as single source of truth
# Both ExternalSecret and Terraform read from this Vault path

resource "random_password" "harbor_admin" {
  length  = 32
  special = false

  lifecycle {
    ignore_changes = [length, special]
  }
}

resource "vault_kv_secret_v2" "harbor_admin_password" {
  mount = "kv"
  name  = "harbor/admin"

  data_json = jsonencode({
    password = random_password.harbor_admin.result
  })

  lifecycle {
    ignore_changes = [data_json]
  }
}
