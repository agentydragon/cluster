#!/bin/bash
set -e

# Run this after terraform apply to verify cluster health
# Configuration is extracted from terraform outputs

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "== Cluster Health Check =="

# Get node lists
CONTROLLERS=($(terraform output -json controllers 2>/dev/null | jq -r '.[]' || { echo "❌ Failed to get controllers from terraform"; exit 1; }))
WORKERS=($(terraform output -json workers 2>/dev/null | jq -r '.[]' || { echo "❌ Failed to get workers from terraform"; exit 1; }))
ALL_NODES=($(terraform output -json all_nodes 2>/dev/null | jq -r 'to_entries[] | .value.ip_address' || { echo "❌ Failed to get all_nodes from terraform"; exit 1; }))

# Get cluster configuration (all timeouts, ports, paths from terraform)
CLUSTER_CONFIG=$(terraform output -json cluster_config 2>/dev/null || { echo "❌ Failed to get cluster_config from terraform"; exit 1; })
VIP=$(echo "$CLUSTER_CONFIG" | jq -r '.vip')
API_PORT=$(echo "$CLUSTER_CONFIG" | jq -r '.api_port')
CONNECT_TIMEOUT=$(echo "$CLUSTER_CONFIG" | jq -r '.connect_timeout')
MAX_TIMEOUT=$(echo "$CLUSTER_CONFIG" | jq -r '.max_timeout')
PING_COUNT=$(echo "$CLUSTER_CONFIG" | jq -r '.ping_count')
PING_TIMEOUT=$(echo "$CLUSTER_CONFIG" | jq -r '.ping_timeout')
KUBECONFIG_FILE=$(echo "$CLUSTER_CONFIG" | jq -r '.kubeconfig_path')
KUBECTL_TIMEOUT=$(echo "$CLUSTER_CONFIG" | jq -r '.kubectl_timeout')

echo "   Controllers: ${CONTROLLERS[*]}"
echo "   Workers: ${WORKERS[*]}"
echo "   All nodes: ${ALL_NODES[*]}"
echo "   VIP: $VIP"
echo "   API port: $API_PORT"
echo

# Validate extracted configuration
if [[ -z "$VIP" || "$VIP" == "null" ]] || [[ ${#CONTROLLERS[@]} -eq 0 ]] || [[ ${#ALL_NODES[@]} -eq 0 ]]; then
    echo "❌ Invalid configuration extracted from terraform"
    exit 1
fi

# Test 1: Node Connectivity
echo "🔗 Testing node connectivity..."
for node in "${ALL_NODES[@]}"; do
    echo -n "   Testing $node... "
    if ping -c "$PING_COUNT" -W "$PING_TIMEOUT" "$node" > /dev/null 2>&1; then
        echo "✅"
    else
        echo "❌ FAILED"
        exit 1
    fi
done
echo

# Test 2: Wait for all nodes to be ready
echo "⏳ Waiting for all nodes to be ready..."
if kubectl wait --for=condition=Ready nodes --all --timeout=120s > /dev/null 2>&1; then
    echo "   All nodes ready ✅"
else
    echo "   ❌ FAILED - some nodes not ready within 120s"
    kubectl get nodes
    exit 1
fi
echo

# Test 3: Controller API Health
echo "🎛️  Testing controller APIs..."
for controller in "${CONTROLLERS[@]}"; do
    echo -n "   Testing https://$controller:$API_PORT/version... "
    if curl -k --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIMEOUT" -s "https://$controller:$API_PORT/version" > /dev/null 2>&1; then
        echo "✅"
    else
        echo "❌ FAILED"
        exit 1
    fi
done
echo

# Test 4: VIP Health
echo "🎯 Testing cluster VIP..."
echo -n "   Testing VIP connectivity ($VIP)... "
if ping -c "$PING_COUNT" -W "$PING_TIMEOUT" "$VIP" > /dev/null 2>&1; then
    echo "✅"
else
    echo "❌ FAILED"
    exit 1
fi

echo -n "   Testing VIP API (https://$VIP:$API_PORT/version)... "
if curl -k --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIMEOUT" -s "https://$VIP:$API_PORT/version" > /dev/null 2>&1; then
    echo "✅"
else
    echo "❌ FAILED"
    exit 1
fi
echo

# Test 5: Kubectl access (trust direnv KUBECONFIG)
echo "📋 Testing kubectl access..."
echo "   KUBECONFIG in script: $KUBECONFIG"
echo "   kubectl timeout: $KUBECTL_TIMEOUT"
echo -n "   Testing kubectl get nodes... "
if kubectl get nodes --request-timeout="$KUBECTL_TIMEOUT"; then
    echo "✅"
else
    echo "❌ FAILED - kubectl cannot access cluster"
    echo "kubectl version --client:"
    kubectl version --client
    echo "kubectl config current-context:"
    kubectl config current-context
    exit 1
fi

# Optional: Verify VIP reference in current kubeconfig
if [ -n "$KUBECONFIG" ] && [ -f "$KUBECONFIG" ]; then
    echo -n "   Checking VIP reference in kubeconfig... "
    if grep -q "$VIP" "$KUBECONFIG"; then
        echo "✅"
    else
        echo "⚠️  Warning: kubeconfig may not reference VIP"
    fi
fi
echo

# Test 6: Cluster health analysis with Popeye
echo "🔍 Running cluster health analysis..."
if command -v popeye >/dev/null 2>&1; then
    echo "   Running Popeye cluster scan..."
    if popeye --save; then
        echo "   ✅ Popeye scan completed (report saved to popeye-report.html)"
    else
        echo "   ⚠️  Popeye scan completed with issues (check output above)"
    fi
else
    echo "   ⚠️  Popeye not found in PATH - install via shell.nix"
fi
echo

echo "All health checks passed"
echo "Next steps: kubectl get nodes, continue BOOTSTRAP.md"
