---
name: bootstrap-monitor
description: >-
  Monitor cluster bootstrap to completion. Use when user asks to bootstrap, deploy, or bring up
  the cluster. Does NOT return until complete success or irrecoverable failure.
---

# Cluster Bootstrap Monitor

## Purpose

Run `./bootstrap.sh` and monitor the cluster deployment to **complete success or failure**.
This skill enforces continuous monitoring - no intermediate reports, no partial success.

## Exit Conditions (ONLY 2 ALLOWED)

1. **Complete Success**: ALL of the following must be true:
   - All terraform layers applied successfully (00-persistent-auth, 01-infrastructure, 02-services)
   - All nodes Ready (`kubectl get nodes`)
   - All Flux kustomizations reconciled (`flux get kustomizations`)
   - All HelmReleases ready (`flux get helmreleases -A`)
   - Core services responding (Vault, Authentik, PowerDNS, Harbor, Gitea)
   - Health checks passing (HTTP endpoints, DNS resolution)

2. **Irrecoverable Failure**: Error that will not self-heal:
   - Terraform apply failed with non-transient error
   - Pod in CrashLoopBackOff for > 10 minutes
   - PVC stuck Pending for > 5 minutes (storage issue)
   - Certificate generation failed (cert-manager)
   - Database connection failures after pod restarts

## Monitoring Protocol

### Polling Intervals

- **Minimum**: 10 seconds between checks
- **Maximum**: 5 minutes between checks
- Adjust based on what's happening (faster during active deployments)

### Transient Error Handling

When an error occurs that might recover:

1. Note the timestamp when first observed
2. Pre-commit to a timeout (e.g., "HelmRelease flux-system/harbor: expected to reconcile within 5 minutes")
3. Continue monitoring until timeout expires
4. Only declare failure if still broken after timeout

### Health Checks to Perform

```bash
# Nodes
kubectl get nodes

# Flux GitOps
flux get kustomizations
flux get helmreleases -A

# Pods in bad states
kubectl get pods -A | grep -v Running | grep -v Completed

# PVC status
kubectl get pvc -A

# Core services
curl -sk https://auth.test-cluster.agentydragon.com/api/v2/ | head -c 100
curl -sk https://registry.test-cluster.agentydragon.com/api/v2/ | head -c 100
curl -sk https://git.test-cluster.agentydragon.com/ | head -c 100
curl -sk https://vault.test-cluster.agentydragon.com/v1/sys/health | head -c 100

# DNS (PowerDNS)
dig @10.0.3.3 auth.test-cluster.agentydragon.com +short

# Certificates
kubectl get certificates -A
```

## Expected Timeouts

Reference these when deciding if an error is transient:

| Component | Expected Bootstrap Time |
|-----------|------------------------|
| Terraform infrastructure | 5-10 minutes |
| Cilium CNI ready | 2-3 minutes |
| Flux initial sync | 2-3 minutes |
| Vault initialization | 3-5 minutes |
| Authentik ready | 5-8 minutes |
| PowerDNS ready | 2-3 minutes |
| Harbor ready | 5-8 minutes |
| Gitea ready | 3-5 minutes |
| All HelmReleases reconciled | 15-20 minutes total |

## Command Reference

```bash
# Run bootstrap
cd /home/agentydragon/code/cluster && ./bootstrap.sh

# Use direnv for kubectl/talosctl
direnv exec /home/agentydragon/code/cluster kubectl get nodes
direnv exec /home/agentydragon/code/cluster flux get kustomizations

# Check Flux logs
kubectl logs -n flux-system deployment/kustomize-controller --tail=50
kubectl logs -n flux-system deployment/helm-controller --tail=50

# Check specific service
kubectl describe helmrelease <name> -n <namespace>
kubectl logs -n <namespace> deployment/<name> --tail=50
```

## DO NOT

- Return to user with partial progress reports ("infrastructure is up, looks good!")
- Declare success before ALL health checks pass
- Give up on transient errors before timeout expires
- Assume "pods are Running" means "service is healthy"
