#!/bin/bash
# Wrapper around terraform that loads Proxmox API token secrets from the
# shared Ansible Vault (same file used in ~/code/ducktape).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_FILE="$HOME/code/ducktape/ansible/terraform-secrets.vault"
VAULT_SECRET_LABEL="ansible-vault ducktape"
TOKEN_ID_KEY="vault_proxmox_terraform_token_id"
TOKEN_SECRET_KEY="vault_proxmox_terraform_token_secret"
HEADSCALE_KEY_NAME="vault_headscale_api_key"

if [[ ! -f "$VAULT_FILE" ]]; then
  echo "Error: Vault file not found at $VAULT_FILE" >&2
  exit 1
fi

VAULT_PASS=$(secret-tool lookup service ansible-vault account ducktape 2>/dev/null) || {
  echo "Error: Could not retrieve Ansible Vault password from keyring (label: $VAULT_SECRET_LABEL)." >&2
  exit 1
}

VAULT_CONTENT=$(printf "%s" "$VAULT_PASS" | ansible-vault view --vault-password-file=/dev/stdin "$VAULT_FILE" 2>/dev/null) || {
  echo "Error: Unable to decrypt $VAULT_FILE" >&2
  exit 1
}

TOKEN_ID=$(printf '%s\n' "$VAULT_CONTENT" | awk "/^${TOKEN_ID_KEY}:/ { gsub(\"\\\"\", \"\", \$2); print \$2 }")
TOKEN_SECRET=$(printf '%s\n' "$VAULT_CONTENT" | awk "/^${TOKEN_SECRET_KEY}:/ { gsub(\"\\\"\", \"\", \$2); print \$2 }")
HEADSCALE_KEY=$(printf '%s\n' "$VAULT_CONTENT" | awk "/^${HEADSCALE_KEY_NAME}:/ { gsub(\"\\\"\", \"\", \$2); print \$2 }")

if [[ -z "$TOKEN_ID" || -z "$TOKEN_SECRET" ]]; then
  echo "Error: Missing $TOKEN_ID_KEY or $TOKEN_SECRET_KEY in $VAULT_FILE" >&2
  exit 1
fi

if [[ -z "$HEADSCALE_KEY" ]]; then
  echo "Warning: Missing $HEADSCALE_KEY_NAME in $VAULT_FILE - Tailscale extension will be disabled" >&2
fi

export TF_VAR_pm_api_token_id="$TOKEN_ID"
export TF_VAR_pm_api_token_secret="$TOKEN_SECRET"
export TF_VAR_headscale_api_key="$HEADSCALE_KEY"

cd "$SCRIPT_DIR"

echo "Running: terraform $*"
exec terraform "$@"
