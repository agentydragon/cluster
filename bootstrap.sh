#!/bin/bash
# LAYERED TALOS CLUSTER BOOTSTRAP SCRIPT
# This is the ONLY supported way to bootstrap the cluster
#
# Multi-phase deployment with proper service availability checks
# Phase 1: Infrastructure (VMs, Talos, CNI, Storage)
# Phase 2: Services (Deploy via GitOps)
# Phase 3: Configuration (Configure via APIs)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/terraform"

echo "🚀 Starting layered Talos cluster bootstrap..."
echo "📂 Terraform directory: ${TERRAFORM_DIR}"

# Environment variables no longer required - defaults hardcoded in terraform

# Phase 0: Preflight Validation
echo ""
echo "🔍 Phase 0: Preflight Validation"
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

# Validate each layer's terraform configuration
for layer in "01-infrastructure" "02-services" "03-configuration"; do
    echo "🔍 Validating terraform layer: ${layer}..."
    cd "${TERRAFORM_DIR}/${layer}"
    if ! terraform validate; then
        echo "❌ FATAL: Terraform configuration is invalid in layer ${layer}"
        exit 1
    fi
done

# Phase 1: Infrastructure Layer
echo ""
echo "⚡ Phase 1: Infrastructure Deployment"
echo "====================================="

cd "${TERRAFORM_DIR}/01-infrastructure"
echo "🚀 Deploying infrastructure layer..."
echo "     📋 PVE-AUTH → VMs → TALOS → CILIUM → FLUX → STORAGE"

if ! terraform apply -auto-approve; then
    echo "❌ FATAL: Infrastructure deployment failed"
    exit 1
fi

# Verify infrastructure readiness
echo "🔍 Verifying infrastructure readiness..."
KUBECONFIG_PATH="$(terraform output -raw kubeconfig)"
export KUBECONFIG="$KUBECONFIG_PATH"

# Wait for cluster API
echo "⏳ Waiting for Kubernetes API..."
timeout 300 bash -c 'until kubectl cluster-info; do sleep 5; done'

# Wait for all nodes ready
echo "⏳ Waiting for all nodes to be ready..."
timeout 600 bash -c 'until [ $(kubectl get nodes --no-headers | grep Ready | wc -l) -eq 6 ]; do sleep 10; done'

# Phase 2: Services Layer
echo ""
echo "⚡ Phase 2: Services Deployment"
echo "==============================="

cd "${TERRAFORM_DIR}/02-services"
echo "🚀 Deploying services layer..."
echo "     📋 GITOPS → AUTHENTIK → POWERDNS → HARBOR → GITEA → MATRIX"

if ! terraform apply -auto-approve; then
    echo "❌ FATAL: Services deployment failed"
    exit 1
fi

# Wait for critical services to be ready
echo "⏳ Waiting for services to be ready..."

# Wait for Authentik
echo "⏳ Waiting for Authentik deployment..."
timeout 300 bash -c 'until kubectl get deployment authentik -n authentik-system 2>/dev/null; do sleep 10; done'
kubectl wait --for=condition=available deployment/authentik -n authentik-system --timeout=600s

# Wait for PowerDNS
echo "⏳ Waiting for PowerDNS deployment..."
timeout 300 bash -c 'until kubectl get deployment powerdns -n powerdns-system 2>/dev/null; do sleep 10; done'
kubectl wait --for=condition=available deployment/powerdns -n powerdns-system --timeout=600s

# Wait for PowerDNS API to be responsive
echo "⏳ Waiting for PowerDNS API to be ready..."
CLUSTER_VIP="10.0.3.1"  # TODO: Get from terraform output
timeout 300 bash -c "until curl -sf http://${CLUSTER_VIP}:8081/api/v1/servers; do sleep 5; done"

# Phase 3: Configuration Layer (Optional - requires API keys)
echo ""
echo "⚡ Phase 3: Configuration (Optional)"
echo "===================================="

# Check if API credentials are provided
cd "${TERRAFORM_DIR}/03-configuration"

if [[ -n "${TF_VAR_powerdns_api_key}" && -n "${TF_VAR_authentik_token}" ]]; then
    echo "🚀 API credentials provided - deploying configuration layer..."
    echo "     📋 DNS ZONES → SSO CONFIG → SERVICE INTEGRATION"

    if ! terraform apply -auto-approve; then
        echo "❌ WARNING: Configuration deployment failed"
        echo "💡 Services are deployed but may need manual configuration"
        exit 1
    fi

    echo "🎉 Full cluster configuration completed!"
else
    echo "⚠️  Phase 3 skipped - API credentials not provided"
    echo "💡 To complete configuration:"
    echo "   1. Retrieve API keys from deployed services"
    echo "   2. Export TF_VAR_powerdns_api_key=<key>"
    echo "   3. Export TF_VAR_authentik_token=<token>"
    echo "   4. Re-run: cd terraform/03-configuration && terraform apply"
fi

echo ""
echo "🎉 Layered cluster bootstrap completed!"
echo "📊 Layer status:"
echo "   ✅ Phase 1: Infrastructure deployed"
echo "   ✅ Phase 2: Services deployed"
if [[ -n "${TF_VAR_powerdns_api_key}" ]]; then
    echo "   ✅ Phase 3: Configuration deployed"
else
    echo "   ⚠️  Phase 3: Configuration pending (API keys needed)"
fi
echo ""
echo "🔗 Access cluster: export KUBECONFIG='${KUBECONFIG_PATH}'"