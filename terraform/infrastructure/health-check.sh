#!/bin/bash
set -e

# Talos Cluster Health Check Script
# Run this after terraform apply to verify cluster health
# All configuration is extracted from terraform outputs (DRY principle)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🔍 Talos Cluster Health Check"
echo "=============================="

# Verify required tools
for tool in terraform jq kubectl; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "❌ $tool command not found"
        exit 1
    fi
done

# Extract ALL configuration from terraform outputs (fully DRY)
echo "📊 Reading cluster configuration from terraform..."

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

# Validate extracted configuration
if [[ -z "$VIP" || "$VIP" == "null" ]] || [[ ${#CONTROLLERS[@]} -eq 0 ]] || [[ ${#ALL_NODES[@]} -eq 0 ]]; then
    echo "❌ Invalid configuration extracted from terraform"
    echo "   VIP: $VIP"
    echo "   Controllers: ${#CONTROLLERS[@]}"
    echo "   All nodes: ${#ALL_NODES[@]}"
    exit 1
fi

echo "   Controllers: ${CONTROLLERS[*]}"
echo "   Workers: ${WORKERS[*]}"
echo "   All nodes: ${ALL_NODES[*]}"
echo "   VIP: $VIP"
echo "   API port: $API_PORT"
echo

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

# Test 2: Controller API Health
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

# Test 3: VIP Health
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

# Test 4: Kubeconfig validation (if it exists)
if [ -f "$KUBECONFIG_FILE" ]; then
    echo "📋 Validating kubeconfig..."
    echo -n "   Checking VIP reference in kubeconfig... "
    if grep -q "$VIP" "$KUBECONFIG_FILE"; then
        echo "✅"
    else
        echo "❌ FAILED - kubeconfig does not reference VIP"
        exit 1
    fi

    echo -n "   Testing kubectl access... "
    if KUBECONFIG="$KUBECONFIG_FILE" kubectl get nodes --timeout="$KUBECTL_TIMEOUT" > /dev/null 2>&1; then
        echo "✅"
    else
        echo "❌ FAILED - kubectl cannot access cluster"
        exit 1
    fi
else
    echo "⚠️  Kubeconfig file not found at $KUBECONFIG_FILE"
fi
echo

echo "🎉 All health checks passed!"
echo
echo "Next steps:"
echo "   export KUBECONFIG=$KUBECONFIG_FILE"
echo "   kubectl get nodes"