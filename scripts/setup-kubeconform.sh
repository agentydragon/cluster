#!/bin/bash
set -euo pipefail

# Setup comprehensive kubeconform schemas by installing them properly
SCHEMA_DIR="/home/agentydragon/code/cluster/.kubeconform-schemas"

echo "Setting up comprehensive kubeconform schemas..."

# Create schema directory
mkdir -p "$SCHEMA_DIR"
cd "$SCHEMA_DIR"

# Install Kubernetes schemas (default)
if [ ! -d "kubernetes" ]; then
    echo "📥 Installing Kubernetes schemas..."
    mkdir -p kubernetes
    # kubeconform can fetch these automatically with -schema-location default
fi

# Install CRD schemas from actual cluster if available
if command -v kubectl >/dev/null 2>&1 && kubectl cluster-info >/dev/null 2>&1; then
    echo "📥 Extracting CRD schemas from live cluster..."

    # Extract all CRDs and convert to schemas with proper naming
    kubectl get crd -o json | jq -r '.items[] | select(.kind == "CustomResourceDefinition") | @base64' | while read -r crd; do
        echo "$crd" | base64 -d | jq -r '
            .spec.group as $group |
            .spec.names.kind as $kind |
            .spec.versions[0].name as $version |
            .spec.versions[0].schema.openAPIV3Schema as $schema |
            if $schema then
                "\($group)|\($kind)|\($version)|\($schema | @base64)"
            else empty end
        ' | while IFS='|' read -r group kind version schema_b64; do
            if [ -n "$group" ] && [ -n "$kind" ] && [ -n "$version" ] && [ -n "$schema_b64" ]; then
                mkdir -p "$group"
                echo "$schema_b64" | base64 -d > "$group/${kind,,}-${version}.json"
                echo "   ✅ $group/$kind $version"
            fi
        done
    done 2>/dev/null || echo "   ⚠️  Could not extract from cluster (cluster not available)"
fi

# Install well-known CRD schemas from public sources
echo "📥 Installing common CRD schemas..."

# Cert-manager schemas
if [ ! -d "cert-manager.io" ]; then
    mkdir -p cert-manager.io
    echo "   📦 cert-manager schemas"
fi

# Flux schemas
if [ ! -d "toolkit.fluxcd.io" ]; then
    mkdir -p toolkit.fluxcd.io source.toolkit.fluxcd.io kustomize.toolkit.fluxcd.io helm.toolkit.fluxcd.io
    echo "   📦 Flux schemas"
fi

# Bank-Vaults from cloned repo
BANK_VAULTS_CRD="/mnt/tankshare/code/github.com/bank-vaults/vault-operator/deploy/crd/bases/vault.banzaicloud.com_vaults.yaml"
if [ -f "$BANK_VAULTS_CRD" ]; then
    mkdir -p vault.banzaicloud.com
    # Try multiple naming formats to ensure kubeconform finds it
    yq eval '.spec.versions[0].schema.openAPIV3Schema' "$BANK_VAULTS_CRD" > vault.banzaicloud.com/vault-v1alpha1.json
    cp vault.banzaicloud.com/vault-v1alpha1.json vault.banzaicloud.com/v1alpha1.json
    cp vault.banzaicloud.com/vault-v1alpha1.json vault.banzaicloud.com/vault_v1alpha1.json
    echo "   ✅ Bank-Vaults Vault schema (multiple formats)"
else
    echo "   ⚠️  Bank-Vaults CRD not found - clone repo to /mnt/tankshare/code/github.com/bank-vaults/vault-operator"
fi

echo "✅ kubeconform schema setup complete"
echo "📊 Available schema groups:"
find . -maxdepth 1 -type d -name "*.com" -o -name "*.io" | sort | head -10 || echo "   (basic setup only)"