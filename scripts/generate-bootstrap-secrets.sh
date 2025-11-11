#!/usr/bin/env bash
set -euo pipefail

# This script generates SealedSecrets for bootstrap tokens
# Run this AFTER sealed-secrets controller is deployed

echo "🔐 Generating bootstrap SealedSecrets..."

# Check if sealed-secrets controller is ready
if ! kubectl get pods -n flux-system -l app.kubernetes.io/name=sealed-secrets | grep -q Running; then
    echo "❌ sealed-secrets controller is not running. Deploy it first:"
    echo "   flux reconcile ks flux-system"
    exit 1
fi

# Generate Vault bootstrap secret
echo "🗝️  Generating Vault bootstrap token..."
VAULT_TOKEN=$(openssl rand -hex 32)
echo -n "$VAULT_TOKEN" | kubectl create secret generic vault-bootstrap \
    --from-file=root-token=/dev/stdin \
    --namespace=vault \
    --dry-run=client -o yaml | \
    kubeseal --controller-name=sealed-secrets --controller-namespace=flux-system -o yaml > k8s/infrastructure/platform/vault/vault-bootstrap-sealed.yaml

echo "✅ Created k8s/infrastructure/platform/vault/vault-bootstrap-sealed.yaml"

# Generate Authentik bootstrap secret  
echo "🔑 Generating Authentik bootstrap token..."
AUTHENTIK_TOKEN=$(openssl rand -hex 32)
echo -n "$AUTHENTIK_TOKEN" | kubectl create secret generic authentik-bootstrap \
    --from-file=bootstrap-token=/dev/stdin \
    --namespace=authentik \
    --dry-run=client -o yaml | \
    kubeseal --controller-name=sealed-secrets --controller-namespace=flux-system -o yaml > k8s/infrastructure/platform/authentik/authentik-bootstrap-sealed.yaml

echo "✅ Created k8s/infrastructure/platform/authentik/authentik-bootstrap-sealed.yaml"

echo ""
echo "🎉 Bootstrap secrets generated!"
echo ""
echo "Next steps:"
echo "1. Add the sealed secrets to their respective kustomizations"
echo "2. Update HelmReleases to reference the secrets"
echo "3. Commit and push the sealed secrets to Git"
echo ""
echo "Vault root token: $VAULT_TOKEN"
echo "Authentik bootstrap: $AUTHENTIK_TOKEN"
echo ""
echo "⚠️  Save these tokens securely - you'll need them for initial setup!"