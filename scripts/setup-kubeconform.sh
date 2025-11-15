#!/bin/bash
set -euo pipefail

# Setup kubeconform for Bank-Vaults validation
SCHEMA_DIR="/home/agentydragon/code/cluster/.kubeconform-schemas"
BANK_VAULTS_CRD="/mnt/tankshare/code/github.com/bank-vaults/vault-operator/deploy/crd/bases/vault.banzaicloud.com_vaults.yaml"

echo "Setting up kubeconform schemas for Bank-Vaults..."

# Create schema directory
mkdir -p "$SCHEMA_DIR/vault.banzaicloud.com"

# Extract Bank-Vaults Vault CRD schema
if [ -f "$BANK_VAULTS_CRD" ]; then
    echo "Extracting Bank-Vaults Vault schema..."

    # Create the schema in the format kubeconform expects
    # Format: {group}/{version}/{kind}_v{version}.json
    yq eval '.spec.versions[0].schema.openAPIV3Schema' "$BANK_VAULTS_CRD" > "$SCHEMA_DIR/vault.banzaicloud.com/vault-v1alpha1.json"

    echo "✅ Extracted schema to $SCHEMA_DIR/vault.banzaicloud.com/vault-v1alpha1.json"

    # Also create alternative naming format
    cp "$SCHEMA_DIR/vault.banzaicloud.com/vault-v1alpha1.json" "$SCHEMA_DIR/vault.banzaicloud.com/v1alpha1.json"

else
    echo "⚠️  Bank-Vaults CRD not found at $BANK_VAULTS_CRD"
    echo "   Please ensure Bank-Vaults repository is cloned to /mnt/tankshare/code/github.com/bank-vaults/vault-operator"
fi

echo "✅ kubeconform setup complete"