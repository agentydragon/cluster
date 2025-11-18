# Cluster Troubleshooting Checklist

Quick diagnostic commands for common cluster issues.

## Known Issues

### Zombie Kubelet (Containerd Crash Recovery Failure)

**Symptoms**:

- Node shows Ready in `kubectl get nodes` but pods stuck in Pending
- `talosctl service kubelet status` shows: `STATE: Failed`, `HEALTH: Fail`, `service not running`
- Error: "cannot delete running task kubelet: failed precondition"
- Some pods (cilium, sealed-secrets) running but new pods cannot start
- CSI volume attachment succeeds but mount operations never happen

**Root Cause**:

- Containerd crashes (exit status 2) while kubelet is running
- Kubelet process and containerd-shim survive as orphaned processes
- Containerd restarts but loses tracking of the old kubelet container
- Talos service manager cannot delete the orphaned kubelet container to start new one

**Diagnosis**:

```bash
# Check service status
talosctl -n <node-ip> service kubelet status

# Look for zombie kubelet process
talosctl -n <node-ip> ps | grep kubelet

# Check events for failure pattern
talosctl -n <node-ip> events | grep kubelet

# Look for: "PREPARING: Creating service runner" → "FAILED: cannot delete running task"
```

**Resolution**:

1. **Reboot the affected node** (cleanest recovery):

   ```bash
   talosctl -n <node-ip> reboot
   ```

2. **Alternative** (riskier - may disrupt running pods):

   ```bash
   # Find zombie kubelet PID
   talosctl -n <node-ip> ps | grep kubelet

   # Force kill the process and shim
   talosctl -n <node-ip> kill <kubelet-pid>
   talosctl -n <node-ip> kill <shim-pid>
   ```

**Prevention**:

- Unknown - containerd crash cause needs further investigation
- Monitor containerd logs for warning signs
- Consider containerd log retention increase for crash analysis

**Historical Occurrence**:

- 2025-11-17: worker0 - containerd crashed with exit status 2, left kubelet PID 89823 orphaned
- Logs rotated before crash investigation possible

## 🚨 Fast Path Health Checks

### Core Cluster Health

```bash
kubectl get nodes                           # All nodes should be Ready
kubectl get pods -A | grep -v Running      # Check for non-running pods
flux get kustomizations                     # Check GitOps status
```

### Storage (Proxmox CSI) - Known Tricky Component

**Common Issues**: SealedSecret decryption failures, authentication errors with misleading messages.

```bash
# 1. Check CSI pods status
kubectl get pods -n csi-proxmox

# 2. Check PVC status (if vault/storage apps are Pending)
kubectl get pvc -A
# Look for Pending PVCs

# 3. Check CSI controller logs for auth errors
kubectl logs deployment/proxmox-csi-plugin-controller -n csi-proxmox --tail=20
# Look for "401 Unauthorized" - often misleading, usually means missing token in Proxmox

# 4. Check SealedSecret health
kubectl get sealedsecret -n csi-proxmox
# STATUS should be empty (success) or show decryption error

# 5. Check if secret was created and has correct content
kubectl get secret -n csi-proxmox proxmox-csi-plugin
kubectl get secret proxmox-csi-plugin -n csi-proxmox -o jsonpath='{.data.config\.yaml}' | base64 -d

# 6. If SealedSecret shows decryption error, regenerate with stable keypair:
CSI_TOKEN_SECRET=$(secret-tool lookup service proxmox-csi key token_secret)
cat > /tmp/csi-config.yaml << EOF
clusters:
- insecure: false
  region: "cluster"
  token: "kubernetes-csi@pve!csi=$CSI_TOKEN_SECRET"
  token_id: "kubernetes-csi@pve!csi"
  token_secret: "$CSI_TOKEN_SECRET"
  url: "https://atlas.agentydragon.com/api2/json"
EOF

kubectl create secret generic proxmox-csi-plugin \
  --namespace=csi-proxmox \
  --from-file=config.yaml=/tmp/csi-config.yaml \
  --dry-run=client -o yaml | \
kubeseal --cert <(secret-tool lookup service sealed-secrets key public_key) \
  --format=yaml | kubectl apply -f -

rm /tmp/csi-config.yaml

# 7. Check if CSI token exists in Proxmox (via SSH)
ssh root@atlas "pveum token list kubernetes-csi@pve"
# Should show the csi token, if missing need to recreate via infrastructure terraform
```

### Node Issues

**Worker Node NotReady** (common: kubelet disk detection issues):

```bash
kubectl describe node <node-name>
# Look for: "InvalidDiskCapacity" errors in events
# Fix: Usually resolves on its own, or restart the node VM
```

### GitOps Issues

**Kustomization stuck/failing**:

```bash
kubectl describe kustomization <name> -n flux-system
kubectl logs deployment/kustomize-controller -n flux-system --tail=50
```

**HelmRelease stuck/failing**:

```bash
kubectl describe helmrelease <name> -n <namespace>
kubectl logs deployment/helm-controller -n flux-system --tail=50
```

## 🔧 Stable SealedSecret Keypair Issues

### Keypair Verification

```bash
# Check if stable keypair exists
secret-tool lookup service sealed-secrets key private_key >/dev/null && echo "✅ Private key exists"
secret-tool lookup service sealed-secrets key public_key >/dev/null && echo "✅ Public key exists"

# Check if cluster is using stable keypair
kubectl get secret sealed-secrets-key -n kube-system -o jsonpath='{.data.tls\.crt}' | \
  base64 -d | openssl x509 -text -noout | grep -A2 "Serial Number"
secret-tool lookup service sealed-secrets key public_key | openssl x509 -text -noout | grep -A2 "Serial Number"
# Serial numbers should match
```

### SealedSecret Decryption Test

```bash
# Test if a SealedSecret can be decrypted with stable keypair
kubectl get sealedsecret <name> -n <namespace> -o yaml | \
kubeseal --recovery-unseal --recovery-private-key <(secret-tool lookup service sealed-secrets key private_key)
# Should output the original secret YAML if working
```

## 🔄 Common Recovery Actions

### Restart Flux Controllers (for CRD cache issues)

```bash
kubectl rollout restart deployment/kustomize-controller -n flux-system
kubectl rollout restart deployment/helm-controller -n flux-system
```

### Force GitOps Reconciliation

```bash
kubectl annotate kustomization <name> -n flux-system fluxcd.io/reconcile="$(date +%s)" --overwrite
```

### Emergency CSI Secret Fix (storage broken)

```bash
# Delete broken SealedSecret and recreate with stable keypair
kubectl delete sealedsecret proxmox-csi-plugin -n csi-proxmox
# Then run the CSI secret regeneration from storage section above
```

## 🐛 Known Issues

### Proxmox CSI Storage

- **Issue**: SealedSecret decryption failures
- **Cause**: terraform/storage generating secrets with wrong keypair
- **Fix**: Always use stable keypair from libsecret when sealing

### Flux CRD Caching

- **Issue**: "no matches for kind" errors after CRD deployment
- **Cause**: Controller cache doesn't auto-refresh for new CRDs
- **Fix**: Restart kustomize-controller (usually resolves automatically)

### Worker Node Kubelet Issues

- **Issue**: Node stuck NotReady with "InvalidDiskCapacity"
- **Cause**: Kubelet disk detection problems
- **Fix**: Usually resolves automatically, or restart VM
