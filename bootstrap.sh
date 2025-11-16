#!/bin/bash
# Consolidated Talos Cluster Bootstrap Script
# This is the ONLY supported way to bootstrap the cluster
#
# Performs complete preflight validation before running terraform apply
# Ensures turnkey deployment: validation → pve-auth → infrastructure → gitops

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/terraform-consolidated"

echo "🚀 Starting consolidated Talos cluster bootstrap..."
echo "📂 Terraform directory: ${TERRAFORM_DIR}"

# Phase 1: Preflight Validation
echo ""
echo "🔍 Phase 1: Preflight Validation"
echo "=================================="

# Check git working tree is clean
if ! git diff-index --quiet HEAD --; then
    echo "❌ FATAL: Git working tree is not clean"
    echo "Please commit or stash your changes before running bootstrap"
    exit 1
fi

# Run pre-commit validation
echo "🔍 Running pre-commit validation..."
if ! pre-commit run --all-files; then
    echo "❌ FATAL: Pre-commit validation failed"
    exit 1
fi

# Validate terraform configuration
echo "🔍 Validating terraform configuration..."
cd "${TERRAFORM_DIR}"
if ! terraform validate; then
    echo "❌ FATAL: Terraform configuration is invalid"
    exit 1
fi

# Phase 2: Layer-by-layer deployment
echo ""
echo "⚡ Phase 2: Layer-by-layer Deployment"
echo "===================================="

# PVE-AUTH layer
echo "🔧 Deploying PVE-AUTH layer..."
if ! terraform apply -var="deploy_layer=pve-auth" -auto-approve; then
    echo "❌ FATAL: PVE-AUTH layer deployment failed"
    exit 1
fi
echo "✅ PVE-AUTH layer deployed successfully"

# INFRASTRUCTURE layer
echo "🏗️  Deploying INFRASTRUCTURE layer..."
if ! terraform apply -var="deploy_layer=infrastructure" -auto-approve; then
    echo "❌ FATAL: INFRASTRUCTURE layer deployment failed"
    exit 1
fi
echo "✅ INFRASTRUCTURE layer deployed successfully"

# GITOPS layer (when implemented)
# echo "🚢 Deploying GITOPS layer..."
# terraform apply -var="deploy_layer=gitops" -auto-approve
# echo "✅ GITOPS layer deployed successfully"

echo ""
echo "🎉 Cluster bootstrap completed successfully!"
echo "🔗 All layers deployed with centralized provider version management"