# Vault Raft Multi-Node Cluster Formation - Research Report

## Root Cause Analysis

**THE REAL PROBLEM**: We're **overconfiguring** and **fighting the Bank-Vaults operator's built-in automation**.

### Key Findings

1. **retry_join is UNNECESSARY** with Bank-Vaults operator - the operator handles cluster formation automatically
2. **api_addr and cluster_addr are UNNECESSARY** - they're auto-detected in Kubernetes environments
3. **Explicit address configuration conflicts** with Bank-Vaults service discovery automation
4. **We're making it too complex** - minimal configs work better with operators

## Current Config Issues

### ❌ **Overcomplex Configuration Causing Conflicts:**

```yaml
# OUR CURRENT CONFIG (PROBLEMATIC):
config:
  storage:
    raft:
      path: "/vault/file"
      retry_join:  # ❌ UNNECESSARY - Bank-Vaults handles this
        - leader_api_addr: "http://instance-0.instance.vault.svc.cluster.local:8200"
  api_addr: "http://instance.vault.svc.cluster.local:8200"      # ❌ UNNECESSARY - Auto-detected
  cluster_addr: "http://instance.vault.svc.cluster.local:8201"  # ❌ UNNECESSARY - Auto-detected
  log_level: "debug"  # ❌ UNNECESSARY - Too verbose
```

### ✅ **Minimal Working Configuration:**

```yaml
# SIMPLIFIED VERSION (SHOULD WORK):
config:
  storage:
    raft:
      path: "/vault/file"  # ✅ ONLY THIS IS NEEDED
  listener:
    tcp:
      address: "0.0.0.0:8200"
      tls_disable: true
  ui: true
```

## Official HashiCorp Best Practices

### Canonical 3-Node Bootstrap Sequence

1. **Initialize first node** (vault-0)
2. **Join additional nodes** manually to leader
3. **Unseal all nodes** individually

**Key Insight**: Bank-Vaults operator should handle steps 1-2 automatically if we don't interfere with overconfiguration.

## Troubleshooting Commands for Current Issue

```bash
# Check autopilot status and configuration
VAULT_TOKEN=$(kubectl get secret -n vault instance-unseal-keys -o jsonpath='{.data.vault-root}' | base64 -d)
kubectl exec -n vault instance-0 -c vault -- sh -c "
  export VAULT_ADDR=http://127.0.0.1:8200
  export VAULT_TOKEN=$VAULT_TOKEN
  vault operator raft autopilot get-config"

# Check what peers exist
kubectl exec -n vault instance-0 -c vault -- sh -c "
  export VAULT_ADDR=http://127.0.0.1:8200
  export VAULT_TOKEN=$VAULT_TOKEN
  vault operator raft list-peers"

# Disable autopilot safety to allow cluster formation
kubectl exec -n vault instance-0 -c vault -- sh -c "
  export VAULT_ADDR=http://127.0.0.1:8200
  export VAULT_TOKEN=$VAULT_TOKEN
  vault operator raft autopilot set-config \\
    -cleanup-dead-servers=false \\
    -min-quorum=0"
```

## The Fix

**STEP 1**: Simplify configuration dramatically - remove retry_join, api_addr, cluster_addr
**STEP 2**: Let Bank-Vaults operator handle cluster formation automatically
**STEP 3**: Only specify the essentials: storage path, listener, UI

## Key Insight

**We were solving the wrong problem!** The issue isn't network configuration or load balancer routing - it's that we're **micromanaging what the operator is designed to handle automatically**.

**Bank-Vaults operator** is built to handle multi-node Raft cluster formation. By specifying explicit retry_join and addresses, we're creating conflicts with the operator's automation.

## Next Steps

1. **Apply simplified configuration** (remove all the bells & whistles)
2. **Delete existing pods** to reset cluster state
3. **Let operator handle cluster formation** naturally
4. **Verify 3-node cluster** forms automatically
