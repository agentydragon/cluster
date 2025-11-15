# Bootstrap PowerDNS API key to break circular dependency
# This generates a random API key and stores it in Vault
# ExternalSecrets will then sync it to Kubernetes for PowerDNS to use

resource "random_password" "powerdns_api_key" {
  length  = 32
  special = false

  lifecycle {
    ignore_changes = all # Don't regenerate on every apply
  }
}

# Store in Vault using the Vault provider
resource "vault_kv_secret_v2" "powerdns_api_key" {
  mount               = "kv"
  name                = "powerdns/api"
  delete_all_versions = true

  data_json = jsonencode({
    api_key = random_password.powerdns_api_key.result
  })

  depends_on = [
    null_resource.wait_for_vault_ready
  ]
}

# Wait for Vault to be ready before storing secrets
resource "null_resource" "wait_for_vault_ready" {
  provisioner "local-exec" {
    command = <<-EOF
      set -e
      echo "Waiting for Vault to be ready..."

      # Wait for Vault pods
      kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=vault -n vault --timeout=300s || true

      # Give Vault a moment to fully initialize
      sleep 10
    EOF
  }

  depends_on = [
    null_resource.wait_for_nodes_ready
  ]
}