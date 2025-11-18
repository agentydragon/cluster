# Cluster Troubleshooting Fast Path Checklist

## Quick Cluster Health Assessment

### Immediate Health Check Commands

```bash
# Node health
kubectl get nodes -o wide
kubectl top nodes

# Pod health across all namespaces
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded

# Recent events (last 1 hour)
kubectl get events -A --sort-by='.firstTimestamp' | tail -20

# Critical system components
kubectl get pods -n kube-system
kubectl get pods -n flux-system

# Storage health
kubectl get pv,pvc -A
kubectl get storageclass

# Network health
kubectl get svc -A | grep -v ClusterIP
kubectl get ingress -A
```bash

### Component-Specific Fast Diagnostics

#### CNI Issues (Network Problems)

```bash
# Check CNI pods
kubectl get pods -n kube-system -l k8s-app=cilium
kubectl logs -n kube-system -l k8s-app=cilium --tail=50

# Network connectivity test
kubectl run tmp-shell --rm -i --tty --image nicolaka/netshoot

# DNS resolution test
kubectl run tmp-dns --rm -i --tty --image busybox -- nslookup kubernetes.default
```bash

#### Storage Issues (PVC/PV Problems)

```bash
# Check storage operator
kubectl get pods -n longhorn-system
kubectl logs -n longhorn-system -l app=longhorn-manager --tail=50

# Check PVC status
kubectl describe pvc <pvc-name> -n <namespace>

# Check node storage capacity
df -h /var/lib/longhorn
```bash

#### Vault Issues (Secret Management Problems)

```bash
# Check Vault pods
kubectl get pods -n vault
kubectl logs -n vault -l app.kubernetes.io/name=vault --tail=50

# Vault status
kubectl exec -n vault vault-0 -- vault status

# Check vault auth methods
kubectl exec -n vault vault-0 -- vault auth list
```bash

#### Cert-Manager Issues (Certificate Problems)

```bash
# Check cert-manager pods
kubectl get pods -n cert-manager
kubectl logs -n cert-manager deployment/cert-manager --tail=50

# Check certificate status
kubectl get certificates,certificaterequests,challenges -A
kubectl describe clusterissuer letsencrypt-prod

# Check ACME challenge logs
kubectl logs -n cert-manager deployment/cert-manager-acme-http-solver --tail=50
```bash

#### DNS Issues (External DNS Problems)

```bash
# Check DNS provider pods
kubectl get pods -n dns-system
kubectl logs -n dns-system deployment/powerdns --tail=50

# Test DNS API
kubectl exec -n dns-system deployment/powerdns -- wget -q -O- http://localhost:8081/api/v1/servers/localhost

# Check external DNS records
dig @<external-dns-ip> <domain>
```bash

## Source Code Analysis Protocol

### Clone Strategy for Debugging

The skill follows the `/code/domain.tld/org/repo` structure:

```bash
/code/
├── github.com/
│   ├── longhorn/longhorn/           # Storage implementation
│   ├── cert-manager/cert-manager/   # Certificate management
│   ├── hashicorp/vault/            # Secret management
│   ├── cilium/cilium/              # CNI implementation
│   ├── metallb/metallb/            # LoadBalancer implementation
│   └── external-secrets/external-secrets/ # Secret operators
├── gitlab.com/
└── git.k3s.agentydragon.com/
```bash

### Source Code Debug Strategy

#### When Component Fails to Start

1. **Clone Source Code**:

   ```bash
   cd /code
   git clone https://github.com/component-org/component-name
   ```

1. **Find Configuration Options**:
   - Check `cmd/` directory for main.go and flag definitions
   - Search for `flag.String`, `viper.Get`, environment variable usage
   - Look in `pkg/config/` or `internal/config/` directories
   - Find example configurations in `examples/` or `docs/`

2. **Identify Debug Options**:
   - Search for log level configurations (`--log-level`, `--debug`, `-v`)
   - Find health check endpoints (`/health`, `/healthz`, `/readiness`)
   - Locate metrics endpoints (`/metrics`, `/prometheus`)
   - Check for profiling endpoints (`/debug/pprof`)

3. **Find Common Issues**:
   - Check `docs/troubleshooting.md` or similar
   - Search GitHub issues for similar problems
   - Look for known limitations in README

### Per-Component Debug Runbooks

#### Longhorn Storage Debug

```bash
# Clone source if not exists
if [ ! -d "/code/github.com/longhorn/longhorn" ]; then
  cd /code/github.com/longhorn && git clone https://github.com/longhorn/longhorn.git
fi

# Check configuration options
grep -r "flag.String\|viper.Get" /code/github.com/longhorn/longhorn/cmd/

# Common debug flags
kubectl patch deployment longhorn-manager -n longhorn-system -p '{"spec":{"template":{"spec":{"containers":[{"name":"longhorn-manager","args":["longhorn-manager","--debug","--log-level","debug"]}]}}}}'

# Check node storage requirements
kubectl get nodes -o jsonpath='{.items[*].status.allocatable.storage}'
```bash

#### Vault Debug

```bash
# Clone vault source
if [ ! -d "/code/github.com/hashicorp/vault" ]; then
  cd /code/github.com/hashicorp && git clone https://github.com/hashicorp/vault.git
fi

# Check debug options from source
grep -r "log_level\|debug" /code/github.com/hashicorp/vault/command/server.go

# Enable debug mode
kubectl patch statefulset vault -n vault -p '{"spec":{"template":{"spec":{"containers":[{"name":"vault","env":[{"name":"VAULT_LOG_LEVEL","value":"debug"}]}]}}}}'

# Check seal status and init
kubectl exec -n vault vault-0 -- vault status -format=json
```bash

#### Cilium CNI Debug

```bash
# Clone cilium source
if [ ! -d "/code/github.com/cilium/cilium" ]; then
  cd /code/github.com/cilium && git clone https://github.com/cilium/cilium.git
fi

# Find debug options
grep -r "debug\|log-level" /code/github.com/cilium/cilium/daemon/cmd/

# Enable debug mode
kubectl patch configmap cilium-config -n kube-system -p '{"data":{"debug":"true","log-level":"debug"}}'
kubectl rollout restart daemonset cilium -n kube-system

# Use cilium CLI for diagnosis
cilium status
cilium connectivity test
```bash

#### Cert-Manager Debug

```bash
# Clone cert-manager source
if [ ! -d "/code/github.com/cert-manager/cert-manager" ]; then
  cd /code/github.com/cert-manager && git clone https://github.com/cert-manager/cert-manager.git
fi

# Check debug flags
grep -r "log-level\|verbose" /code/github.com/cert-manager/cert-manager/cmd/controller/

# Enable verbose logging
kubectl patch deployment cert-manager -n cert-manager -p '{"spec":{"template":{"spec":{"containers":[{"name":"cert-manager","args":["--v=4","--log-level=debug"]}]}}}}'

# Check ACME challenge details
kubectl get challenges -A -o yaml
kubectl logs -n cert-manager deployment/cert-manager-acme-http-solver
```bash

## Error Pattern Recognition

### Common Error Signatures

#### ImagePullBackOff Issues

```bash
# Quick diagnosis
kubectl describe pod <pod-name> | grep -A5 -B5 "Failed to pull image"

# Check registry access
kubectl run test-pull --rm -i --tty --image=<same-image> --command -- /bin/sh
```bash

#### CrashLoopBackOff Issues

```bash
# Get crash logs
kubectl logs <pod-name> --previous

# Check resource limits
kubectl describe pod <pod-name> | grep -A10 "Limits\|Requests"

# Check liveness/readiness probe failures
kubectl describe pod <pod-name> | grep -A5 "Liveness\|Readiness"
```bash

#### Pending Pod Issues

```bash
# Check scheduling issues
kubectl describe pod <pod-name> | grep -A10 "Events"

# Check node capacity
kubectl describe nodes | grep -A5 "Allocated resources"

# Check PVC binding issues
kubectl get pvc -o wide
kubectl describe pvc <pvc-name>
```bash

#### Service Connection Issues

```bash
# Check service endpoints
kubectl get endpoints <service-name> -o wide

# Test service connectivity
kubectl run test-conn --rm -i --tty --image=nicolaka/netshoot -- curl <service-name>.<namespace>:port

# Check network policies
kubectl get networkpolicy -A
```bash

## Rapid Issue Resolution Checklist

### Before Deep Investigation

- [ ] Check if issue is cluster-wide or component-specific
- [ ] Verify basic cluster connectivity (kubectl get nodes)
- [ ] Check recent changes (git log, deployment history)
- [ ] Verify resource availability (CPU, memory, storage, network)

### For Each Failing Component

- [ ] Clone source code to understand configuration options
- [ ] Enable debug logging from source code analysis
- [ ] Check component-specific health endpoints
- [ ] Verify dependencies are healthy
- [ ] Check RBAC and network policies
- [ ] Validate secrets and configmaps exist and are correct

### Documentation Strategy

- [ ] Log all findings in activity log with timestamps
- [ ] Update dependency scratchpad with discovered issues
- [ ] Document debug flags found in source code
- [ ] Record resolution steps for future reference
