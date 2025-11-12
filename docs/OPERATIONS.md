# Talos Cluster Operations

Operational procedures for day-to-day cluster management, scaling, maintenance, and troubleshooting.

## Essential Operations

```bash
# Check cluster health
kubectl get nodes -o wide

# Check Flux status
flux get all

# Force reconciliation  
flux reconcile helmrelease sealed-secrets

# Create sealed secret
kubectl create secret generic my-secret --from-literal=key=value --dry-run=client -o yaml | \
  kubeseal -o yaml > my-sealed-secret.yaml

# Fetch certificate (verify controller access)
kubeseal --fetch-cert
```

## Node Operations

### Adding New Nodes

**Controller Node**
```bash
cd /home/agentydragon/code/cluster/terraform

# Update terraform.tfvars:
# controller_count = 4  # or desired count

# Apply changes
./tf.sh apply

# New controller will automatically join the cluster
# Verify with talosctl get members
```

**Worker Node**
```bash
cd /home/agentydragon/code/cluster/terraform

# Update terraform.tfvars:
# worker_count = 3  # or desired count

# Apply changes
./tf.sh apply

# New worker will automatically join
# Verify with kubectl get nodes
```

### Node Maintenance

**Restart Single Node**
```bash
# Gracefully restart a node (example: controller-1)
talosctl \
  --talosconfig /home/agentydragon/code/cluster/terraform/talosconfig.yml \
  --endpoints 10.0.0.11 \
  --nodes 10.0.0.11 \
  reboot

# Or force restart via Proxmox
ssh root@atlas 'qm reboot 106'
```

**Remove Node**
```bash
# From Kubernetes perspective
kubectl delete node talos-controller-1

# Update terraform.tfvars to reduce count, then:
./tf.sh apply
```

## System Diagnostics

### VM Console Management

**Take VM Screenshots**

See `~/.claude/skills/proxmox-vm-screenshot/vm-screenshot.sh`

**Direct VM Console Access**
```bash
# Interactive console access (from Proxmox host)
ssh root@atlas
qm terminal 106  # controller-1
```

## Troubleshooting Common Issues

### Bootstrap Hanging
**Symptoms**: `talosctl bootstrap` times out or hangs
**Solution**: Verify cluster_endpoint points to first controller IP, not VIP:
```hcl
cluster_endpoint = "https://10.0.0.11:6443"  # NOT 10.0.0.20:6443
```

### Static IP Not Working
**Symptoms**: VMs get DHCP addresses instead of static IPs
**Solution**: Check META key 10 configuration in module and restart VMs

### API Not Responding
**Symptoms**: `connection refused` on port 50000
**Solution**: Wait longer for boot, check console via screenshots

### Network Connectivity Issues
**Symptoms**: Cannot reach VMs on expected IPs
**Solution**: Verify network configuration in terraform.tfvars matches infrastructure

### Let's Encrypt DNS Challenge Fails
**Symptoms**: `REFUSED` responses during certificate creation
**Root Causes & Solutions**:

1. **Missing DNS Delegation** (Most Common):
   - **Symptom**: "No TXT record found at _acme-challenge.domain.com"
   - **Solution**: Add NS delegation record in parent domain DNS (AWS Route 53)
   - **Fix**: `domain.com` → NS → `ns1.agentydragon.com`

2. **PowerDNS TSIG Permission Missing**:
   - **Symptom**: DNS updates rejected with "REFUSED"
   - **Solution**: Add TSIG metadata to zone
   - **Fix**: `pdnsutil set-meta domain.com TSIG-ALLOW-DNSUPDATE certbot`

3. **PowerDNS DNS Update Access Denied**:
   - **Symptom**: "Remote not listed in allow-dnsupdate-from"
   - **Solution**: Add VPS IP to PowerDNS allow list
   - **Fix**: Update `powerdns_allow_dnsupdate_from` in Ansible

### NodePort Services Not Accessible Externally  
**Symptoms**: 502 Bad Gateway or connection refused to NodePorts
**Root Causes & Solutions**:

1. **Cilium kube-proxy Replacement Disabled**:
   - **Symptom**: NodePorts not listening on node interfaces
   - **Solution**: Enable in Cilium configuration
   - **Fix**: `kubeProxyReplacement: "true"`

2. **NodePort Bind Protection Enabled**:
   - **Symptom**: NodePorts only accessible from localhost
   - **Solution**: Disable bind protection in Cilium
   - **Fix**: `nodePort.bindProtection: false`

3. **Wrong Node for NodePort Access**:
   - **Symptom**: Connection refused to specific node
   - **Solution**: Use worker nodes where ingress pods run
   - **Fix**: Target w0/w1 instead of c0/c1/c2 (controllers)

### Worker Nodes Become NotReady
**Symptoms**: `kubectl get nodes` shows workers as "NotReady", pods stuck in Pending
**Root Cause**: Kubelet services stuck waiting for volumes to mount (after restarts/updates)
**Solution**: Restart kubelet services using talosctl
```bash
# Restart kubelet on affected nodes
talosctl -n 10.0.0.21 service kubelet restart  # w0
talosctl -n 10.0.0.22 service kubelet restart  # w1

# Verify nodes return to Ready status
kubectl get nodes
```

### NGINX Ingress Controller in CrashLoopBackOff
**Symptoms**: NGINX controller pods failing to start, "no service found" errors
**Root Causes & Solutions**:

1. **Missing NodePort Service**:
   - **Symptom**: "no service with name ingress-nginx-controller found"
   - **Solution**: Ensure HelmRelease creates proper NodePort service
   - **Fix**: Wait for Flux reconciliation or force with `flux reconcile`

2. **DaemonSet Port Conflicts** (Architecture Issue):
   - **Symptom**: Multiple pods trying to bind same hostNetwork ports
   - **Solution**: Use Deployment instead of DaemonSet
   - **Fix**: Configure `kind: Deployment` with pod anti-affinity

3. **Duplicate HelmReleases**:
   - **Symptom**: Conflicting configurations causing resource conflicts
   - **Solution**: Remove duplicate configurations
   - **Fix**: Keep only one ingress configuration, clean up old namespaces

### Flux Controllers Not Starting
**Symptoms**: Flux pods stuck in ContainerCreating, GitOps not working
**Root Cause**: Worker nodes NotReady prevents pod scheduling
**Solution**: Fix underlying node issues first, then Flux recovers automatically

## Reference Information

### Node IP Assignments

| Node | VM ID | IP Address | Role |
|------|-------|------------|------|
| controller-1 | 106 | 10.0.0.11 | Controller |
| controller-2 | 107 | 10.0.0.12 | Controller |
| controller-3 | 108 | 10.0.0.13 | Controller |
| worker-1 | 109 | 10.0.0.21 | Worker |
| worker-2 | 110 | 10.0.0.22 | Worker |
| **VIP** | - | 10.0.0.20 | Load Balancer |