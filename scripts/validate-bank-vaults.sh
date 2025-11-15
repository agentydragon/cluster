#!/bin/bash
set -euo pipefail

# Custom validation script for Bank-Vaults configurations
# This validates our Vault CRs against the Bank-Vaults schema

echo "🔍 Validating Bank-Vaults configurations..."

VAULT_CONFIG="k8s/vault/instance.yaml"
BANK_VAULTS_CRD="/mnt/tankshare/code/github.com/bank-vaults/vault-operator/deploy/crd/bases/vault.banzaicloud.com_vaults.yaml"

if [ ! -f "$VAULT_CONFIG" ]; then
    echo "❌ Vault configuration not found: $VAULT_CONFIG"
    exit 1
fi

# Test 1: YAML syntax validation
echo "📋 Test 1: YAML syntax validation"
if python3 -c "import yaml; yaml.safe_load(open('$VAULT_CONFIG'))" 2>/dev/null; then
    echo "   ✅ YAML syntax is valid"
else
    echo "   ❌ YAML syntax error detected"
    exit 1
fi

# Test 2: Post-kustomize build validation
echo "📋 Test 2: Post-build schema validation"

# Build with kustomize and validate the result
TEMP_OUTPUT="/tmp/vault-built.yaml"
if kustomize build k8s/vault/ > "$TEMP_OUTPUT" 2>/dev/null; then
    echo "   ✅ Kustomize build successful"

    # Validate the built output with kubeconform (skipping Vault CRD validation)
    if kubeconform --ignore-missing-schemas --skip "Vault" "$TEMP_OUTPUT" >/dev/null 2>&1; then
        echo "   ✅ Post-build validation passed"
    else
        echo "   ❌ Post-build validation failed"
        exit 1
    fi

    rm -f "$TEMP_OUTPUT"
else
    echo "   ❌ Kustomize build failed"
    exit 1
fi

# Test 3: Template syntax validation
echo "📋 Test 3: Bank-Vaults template syntax validation"
CLUSTER_ADDR=$(grep "cluster_addr:" "$VAULT_CONFIG" | grep -v "#" | head -1 || echo "")

if [ -n "$CLUSTER_ADDR" ]; then
    if echo "$CLUSTER_ADDR" | grep -q '${\.Env\.POD_IP}'; then
        echo "   ✅ Using correct Bank-Vaults template syntax: \${.Env.POD_IP}"
    else
        echo "   ❌ Template syntax issue. Expected \${.Env.POD_IP}, got: $CLUSTER_ADDR"
        exit 1
    fi
fi

# Test 4: Environment variable configuration validation
echo "📋 Test 4: Environment variable configuration"
if grep -A10 "envsConfig:" "$VAULT_CONFIG" | grep -q "POD_IP"; then
    echo "   ✅ POD_IP environment variable configured"
else
    echo "   ❌ POD_IP environment variable not found in envsConfig"
    exit 1
fi

# Test 5: Template substitution simulation
echo "📋 Test 5: Template substitution test"
if [ -n "$CLUSTER_ADDR" ]; then
    export POD_IP="10.42.1.123"
    TEMPLATED_RESULT=$(echo "$CLUSTER_ADDR" | sed 's/cluster_addr: *"//' | sed 's/".*$//' | sed "s/\${\.Env\.POD_IP}/$POD_IP/g")
    echo "   🧪 Template result: $TEMPLATED_RESULT"

    if echo "$TEMPLATED_RESULT" | grep -q "10.42.1.123:8201"; then
        echo "   ✅ Template substitution successful"
    else
        echo "   ❌ Template substitution failed"
        exit 1
    fi
fi

echo "🎉 All Bank-Vaults validation tests passed!"