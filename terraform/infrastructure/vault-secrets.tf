# Retrieve secrets from Ansible Vault and convert YAML to JSON
data "external" "vault_secrets" {
  program = [
    "bash", "-c",
    <<-EOT
      VAULT_PASS=$(secret-tool lookup service ansible-vault account ducktape)
      VAULT_YAML=$(printf "%s" "$VAULT_PASS" | ansible-vault view --vault-password-file=/dev/stdin "$HOME/code/ducktape/ansible/terraform-secrets.vault")

      # Convert YAML to JSON for external data source
      echo "$VAULT_YAML" | python3 -c "
import sys, yaml, json
try:
    data = yaml.safe_load(sys.stdin)
    print(json.dumps(data))
except Exception as e:
    print('{\"error\": \"Failed to parse YAML: ' + str(e) + '\"}', file=sys.stderr)
    exit(1)
"
    EOT
  ]
}

locals {
  vault_secrets = data.external.vault_secrets.result
}