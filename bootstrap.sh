#!/bin/bash
# Consolidated Talos Cluster Bootstrap Script
# This is the ONLY supported way to bootstrap the cluster
#
# Performs complete preflight validation before running terraform apply
# Ensures turnkey deployment: validation → pve-auth → infrastructure → gitops

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/terraform"

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

# Phase 2: Single Terraform Apply (All modules with dependencies)
echo ""
echo "⚡ Phase 2: Deploy All Modules"
echo "=============================="

echo "🚀 Deploying all modules with proper dependencies..."
echo "     📋 PVE-AUTH → INFRASTRUCTURE → STORAGE + GITOPS + DNS"

if ! terraform apply -auto-approve; then
    echo "❌ FATAL: Cluster deployment failed"
    exit 1
fi

echo ""
echo "🎉 Cluster bootstrap completed successfully!"
echo "🔗 All modules deployed with proper terraform dependencies"
echo "📊 Use 'terraform output' to view cluster information"