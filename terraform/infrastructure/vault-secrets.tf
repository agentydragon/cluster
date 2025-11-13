# Retrieve secrets from Ansible Vault and convert YAML to JSON
data "external" "vault_secrets" {
  program = [
    "bash", "-c",
    <<-EOT
      VAULT_PASS=$(secret-tool lookup service ansible-vault account ducktape)
      printf "%s" "$VAULT_PASS" | ansible-vault view --vault-password-file=/dev/stdin "$HOME/code/ducktape/ansible/terraform-secrets.vault" | yq -o json
    EOT
  ]
}

locals {
  vault_secrets = data.external.vault_secrets.result
}