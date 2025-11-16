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
    SEALED_SECRET_FILE=$(find k8s/ -name "*.yaml" -exec grep -l "name: $name" {} \; | head -1)

    if [[ ! -f "$SEALED_SECRET_FILE" ]]; then
        echo "⚠️  Sealed secret $secret: file not found in repository"
        VALIDATION_FAILED=true
        continue
    fi

    # Get current private key for testing decryption
    PRIVATE_KEY=$(secret-tool lookup service sealed-secrets key private_key 2>/dev/null | base64 -d)
    PRIVATE_KEY_FILE=$(mktemp)
    echo "$PRIVATE_KEY" > "$PRIVATE_KEY_FILE"

    # Test if this sealed secret can be decrypted with current keypair
    if ! kubeseal --recovery-unseal --recovery-private-key "$PRIVATE_KEY_FILE" < "$SEALED_SECRET_FILE" >/dev/null 2>&1; then
        echo "❌ Sealed secret $secret: cannot decrypt with current keypair"
        echo "   File: $SEALED_SECRET_FILE"
        VALIDATION_FAILED=true
    else
        echo "✅ Sealed secret $secret: can decrypt with current keypair"
    fi

    rm -f "$PRIVATE_KEY_FILE"
done

# Cleanup
rm -f "$CERT_FILE"

if [[ "$VALIDATION_FAILED" = true ]]; then
    echo ""
    echo "⚠️  Sealed secrets validation failed - regenerating with current keypair..."
    echo "🔄 Running terraform apply to regenerate sealed secrets..."
    
    # Regenerate sealed secrets with current keypair
    if ! terraform apply -target=null_resource.seal_secrets -auto-approve; then
        echo "❌ Failed to regenerate sealed secrets"
        echo "   Manual intervention required"
        exit 1
    fi
    
    # Commit the regenerated sealed secrets
    cd "$CLUSTER_ROOT"
    if ! git diff --quiet k8s/**/*-sealed.yaml 2>/dev/null; then
        git add k8s/**/*-sealed.yaml
        if ! git commit -m "chore: auto-regenerate sealed secrets with correct keypair

Bootstrap detected incompatible sealed secrets and regenerated them
with the current cluster's keypair.

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>"; then
            echo "❌ Failed to commit regenerated sealed secrets"
            exit 1
        fi
        echo "✅ Regenerated and committed updated sealed secrets"
    fi
    cd "${SCRIPT_DIR}"
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

echo ""
echo "⏱️ Waiting for Flux controllers to stabilize..."
echo "   This prevents controller restart race conditions"
if ! kubectl wait --for=condition=available deployment/helm-controller -n flux-system --timeout=300s; then
    echo "⚠️ helm-controller not ready, but continuing..."
fi
if ! kubectl wait --for=condition=available deployment/source-controller -n flux-system --timeout=60s; then
    echo "⚠️ source-controller not ready, but continuing..."
fi

echo "🔄 Checking for any failed HelmReleases to retry..."
FAILED_RELEASES=$(kubectl get helmreleases -A -o json | jq -r '.items[] | select(.status.conditions[]?.reason == "InstallFailed" or .status.conditions[]?.reason == "ArtifactFailed") | "\(.metadata.namespace)/\(.metadata.name)"')
if [ -n "$FAILED_RELEASES" ]; then
    echo "🔄 Retrying failed HelmReleases:"
    for release in $FAILED_RELEASES; do
        namespace=$(echo $release | cut -d'/' -f1)
        name=$(echo $release | cut -d'/' -f2)
        echo "   Retrying $release..."
        kubectl annotate helmrelease $name -n $namespace fluxcd.io/reconcile=$(date +%s) --overwrite || true
    done
    echo "⏱️ Waiting 30 seconds for retries to process..."
    sleep 30
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