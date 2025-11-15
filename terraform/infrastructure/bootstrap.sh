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