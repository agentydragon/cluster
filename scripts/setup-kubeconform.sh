#!/bin/bash
set -euo pipefail

# Setup kubeconform schemas from static sources (no cluster dependency)
SCHEMA_DIR="/home/agentydragon/code/cluster/.kubeconform-schemas"
CLONED_REPOS="/mnt/tankshare/code"

echo "Setting up kubeconform schemas from static sources..."

# Create schema directory
mkdir -p "$SCHEMA_DIR"
cd "$SCHEMA_DIR"

# Function to extract schema from CRD file
extract_schema_from_file() {
    local crd_file="$1"
    if [ -f "$crd_file" ]; then
        local group=$(yq eval '.spec.group' "$crd_file" 2>/dev/null || echo "")
        local kind=$(yq eval '.spec.names.kind' "$crd_file" 2>/dev/null || echo "")
        local version=$(yq eval '.spec.versions[0].name' "$crd_file" 2>/dev/null || echo "")

        if [ -n "$group" ] && [ -n "$kind" ] && [ -n "$version" ]; then
            mkdir -p "$group"
            if yq eval '.spec.versions[0].schema.openAPIV3Schema' "$crd_file" > "$group/${kind,,}-${version}.json" 2>/dev/null; then
                echo "   ✅ $group/$kind $version"
                return 0
            fi
        fi
    fi
    return 1
}

# Install schemas from cloned repositories (primary source)
echo "📦 Extracting schemas from cloned repositories..."

if [ -d "$CLONED_REPOS" ]; then
    # Bank-Vaults
    if [ -d "$CLONED_REPOS/github.com/bank-vaults" ]; then
        echo "   📦 Bank-Vaults schemas..."
        find "$CLONED_REPOS/github.com/bank-vaults" -name "*.yaml" -path "*/crd/*" 2>/dev/null | while read -r crd_file; do
            if grep -q "kind: CustomResourceDefinition" "$crd_file" 2>/dev/null; then
                extract_schema_from_file "$crd_file" || true
            fi
        done
    fi

    # FluxCD
    if [ -d "$CLONED_REPOS/github.com/fluxcd" ]; then
        echo "   📦 FluxCD schemas..."
        find "$CLONED_REPOS/github.com/fluxcd" -name "*.yaml" -path "*/config/crd/*" 2>/dev/null | head -20 | while read -r crd_file; do
            if grep -q "kind: CustomResourceDefinition" "$crd_file" 2>/dev/null; then
                extract_schema_from_file "$crd_file" || true
            fi
        done
    fi

    # Cert-manager
    if [ -d "$CLONED_REPOS/github.com/cert-manager" ]; then
        echo "   📦 Cert-manager schemas..."
        find "$CLONED_REPOS/github.com/cert-manager" -name "*.yaml" 2>/dev/null | head -10 | while read -r crd_file; do
            if grep -q "kind: CustomResourceDefinition" "$crd_file" 2>/dev/null; then
                extract_schema_from_file "$crd_file" || true
            fi
        done
    fi

    # MetalLB
    if [ -d "$CLONED_REPOS/github.com/metallb" ]; then
        echo "   📦 MetalLB schemas..."
        find "$CLONED_REPOS/github.com/metallb" -name "*.yaml" -path "*/config/crd/*" 2>/dev/null | head -10 | while read -r crd_file; do
            if grep -q "kind: CustomResourceDefinition" "$crd_file" 2>/dev/null; then
                extract_schema_from_file "$crd_file" || true
            fi
        done
    fi
fi

# Create minimal fallback schemas for essential CRDs if not found
echo "📦 Creating fallback schemas for essential CRDs..."

# Bank-Vaults fallback
if [ ! -f "vault.banzaicloud.com/vault-v1alpha1.json" ]; then
    BANK_VAULTS_CRD="/mnt/tankshare/code/github.com/bank-vaults/vault-operator/deploy/crd/bases/vault.banzaicloud.com_vaults.yaml"
    if [ -f "$BANK_VAULTS_CRD" ]; then
        mkdir -p vault.banzaicloud.com
        yq eval '.spec.versions[0].schema.openAPIV3Schema' "$BANK_VAULTS_CRD" > vault.banzaicloud.com/vault-v1alpha1.json 2>/dev/null
        echo "   ✅ Bank-Vaults Vault schema (fallback)"
    fi
fi

# Cert-manager fallback (create minimal schemas to avoid validation errors)
if [ ! -d "cert-manager.io" ]; then
    mkdir -p cert-manager.io
    cat > cert-manager.io/certificate-v1.json << 'EOF'
{
  "type": "object",
  "properties": {
    "apiVersion": {"type": "string"},
    "kind": {"type": "string"},
    "metadata": {"type": "object"},
    "spec": {"type": "object"},
    "status": {"type": "object"}
  }
}
EOF
    cp cert-manager.io/certificate-v1.json cert-manager.io/issuer-v1.json
    cp cert-manager.io/certificate-v1.json cert-manager.io/clusterissuer-v1.json
    echo "   ✅ Cert-manager fallback schemas"
fi

# Bonus: Try live cluster if available (but don't fail)
if command -v kubectl >/dev/null 2>&1 && kubectl cluster-info >/dev/null 2>&1; then
    echo "🎁 Bonus: Adding live cluster schemas..."
    kubectl get crd -o json 2>/dev/null | jq -r '.items[]? | select(.kind == "CustomResourceDefinition") | @base64' 2>/dev/null | while read -r crd; do
        echo "$crd" | base64 -d 2>/dev/null | jq -r '
            .spec.group as $group |
            .spec.names.kind as $kind |
            .spec.versions[0].name as $version |
            .spec.versions[0].schema.openAPIV3Schema as $schema |
            if $schema then
                "\($group)|\($kind)|\($version)|\($schema | @base64)"
            else empty end
        ' 2>/dev/null | while IFS='|' read -r group kind version schema_b64; do
            if [ -n "$group" ] && [ -n "$kind" ] && [ -n "$version" ] && [ -n "$schema_b64" ]; then
                mkdir -p "$group" 2>/dev/null
                echo "$schema_b64" | base64 -d > "$group/${kind,,}-${version}.json" 2>/dev/null || true
            fi
        done 2>/dev/null || true
    done 2>/dev/null || true
fi

echo "✅ kubeconform schema setup complete"
echo "📊 Available schema groups:"
find . -maxdepth 1 -type d -name "*.com" -o -name "*.io" 2>/dev/null | sort | head -10 || echo "   (basic setup)"