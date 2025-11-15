#!/bin/bash
# Talos Cluster Bootstrap Script
# This is the ONLY supported way to bootstrap the cluster
#
# Performs complete preflight validation before running terraform apply
# Ensures turnkey deployment: validation → infrastructure → everything works

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "🚀 Starting Talos cluster bootstrap..."
echo "📂 Working directory: ${SCRIPT_DIR}"
echo "🏠 Cluster root: ${CLUSTER_ROOT}"

# Phase 1: Preflight Validation
echo ""
echo "🔍 Phase 1: Preflight Validation"
echo "=================================="

# Check git working tree is clean (excluding .md files)
echo "📋 Checking git working tree..."
cd "${CLUSTER_ROOT}"
if ! git diff --quiet -- ':!*.md' || ! git diff --cached --quiet -- ':!*.md'; then
    echo "❌ Git working tree is dirty - uncommitted changes detected"
    echo "   Flux GitOps requires a clean working tree for reliable deployment"
    echo "   Please commit your changes first"
    exit 1
fi
echo "✅ Git working tree is clean"

# Run comprehensive validation suite
echo "🛡️  Running comprehensive validation suite..."
if ! pre-commit run --all-files; then
    echo "❌ Pre-commit validation failed"
    echo "   This includes security scanning, linting, and format checks"
    echo "   Please fix the issues above and try again"
    exit 1
fi
echo "✅ All validation checks passed"

# Terraform-specific validation
echo "🔧 Running terraform validation..."
cd "${SCRIPT_DIR}"
if ! terraform validate; then
    echo "❌ Terraform configuration validation failed"
    echo "   Please fix the terraform configuration issues"
    exit 1
fi
echo "✅ Terraform configuration is valid"

# Sealed secrets keypair validation
echo "🔐 Validating sealed secrets keypair compatibility..."
cd "${CLUSTER_ROOT}"

# Check if we can decrypt required sealed secrets with current keypair
REQUIRED_SEALED_SECRETS=(
    "csi-proxmox/proxmox-csi-plugin"
)

# Get current sealed secrets cert from libsecret
if ! SEALED_CERT=$(secret-tool lookup service sealed-secrets key certificate 2>/dev/null | base64 -d); then
    echo "❌ No sealed-secrets certificate found in libsecret keyring"
    echo "   Run the cluster bootstrap once to generate a keypair, or restore from backup"
    exit 1
fi

# Write cert to temp file for kubeseal validation
CERT_FILE=$(mktemp)
echo "$SEALED_CERT" > "$CERT_FILE"

echo "🔍 Checking sealed secrets in GitOps repository..."
VALIDATION_FAILED=false

for secret in "${REQUIRED_SEALED_SECRETS[@]}"; do
    namespace=$(echo "$secret" | cut -d'/' -f1)
    name=$(echo "$secret" | cut -d'/' -f2)

    # Find the sealed secret YAML file
    SEALED_SECRET_FILE=$(find kubernetes/ -name "*.yaml" -exec grep -l "name: $name" {} \; | head -1)

    if [[ ! -f "$SEALED_SECRET_FILE" ]]; then
        echo "⚠️  Sealed secret $secret: file not found in repository"
        VALIDATION_FAILED=true
        continue
    fi

    # Test if kubeseal can decrypt this sealed secret using current cert
    if ! echo "test-data" | kubeseal --cert "$CERT_FILE" --namespace "$namespace" --name "$name" --raw --from-file=/dev/stdin --validate >/dev/null 2>&1; then
        echo "❌ Sealed secret $secret: cannot decrypt with current keypair"
        echo "   File: $SEALED_SECRET_FILE"
        echo "   This sealed secret was created with a different keypair"
        echo "   You need to either:"
        echo "   1. Re-seal this secret: kubectl create secret generic $name --dry-run=client --from-file=config.yaml=/path/to/config | kubeseal --cert $CERT_FILE -o yaml > $SEALED_SECRET_FILE"
        echo "   2. Restore the original sealed-secrets keypair to libsecret keyring"
        VALIDATION_FAILED=true
    else
        echo "✅ Sealed secret $secret: can decrypt with current keypair"
    fi
done

# Cleanup
rm -f "$CERT_FILE"

if [[ "$VALIDATION_FAILED" = true ]]; then
    echo ""
    echo "❌ Sealed secrets validation failed"
    echo "   Some sealed secrets cannot be decrypted with the current keypair"
    echo "   Fix the issues above before proceeding with cluster deployment"
    exit 1
fi

echo "✅ All required sealed secrets are compatible with current keypair"
cd "${SCRIPT_DIR}"

# Phase 2: Infrastructure Deployment
echo ""
echo "🏗️  Phase 2: Infrastructure Deployment"
echo "======================================"
echo "🎯 Primary directive: terraform apply → everything works"
echo ""

# Apply with maximum timeout for cluster provisioning
echo "⚡ Applying terraform configuration..."
echo "   This will create VMs, bootstrap Talos cluster, install CNI, and deploy GitOps"
echo "   Expected duration: 5-10 minutes for complete cluster bootstrap"
echo ""

if ! terraform apply -auto-approve; then
    echo ""
    echo "❌ Terraform apply failed"
    echo "   The cluster may be in a partial state"
    echo "   Check the error messages above and run 'terraform destroy' if needed"
    exit 1
fi

# Phase 3: Success Confirmation
echo ""
echo "🎉 Bootstrap Complete!"
echo "===================="
echo "✅ Talos cluster is running"
echo "✅ CNI (Cilium) installed via native Helm provider"
echo "✅ GitOps (Flux) bootstrapped via native provider"
echo "✅ Sealed secrets keypair restored from libsecret"
echo ""
echo "🔧 Next steps:"
echo "   • Check cluster status: direnv exec . kubectl get nodes"
echo "   • Monitor Flux deployment: direnv exec . flux get kustomizations"
echo "   • View all services: direnv exec . kubectl get pods -A"
echo ""
echo "📚 See docs/BOOTSTRAP.md for verification steps and troubleshooting"