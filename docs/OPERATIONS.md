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

# Check MetalLB LoadBalancer services
kubectl get svc --all-namespaces -o wide | grep LoadBalancer

# Check MetalLB status
kubectl get pods -n metallb-system
kubectl get ipaddresspools -n metallb-system

# Check PowerDNS
kubectl get pods -n dns-system
kubectl get svc powerdns-external -n dns-system

# Create sealed secret
kubectl create secret generic my-secret --from-literal=key=value --dry-run=client -o yaml | \
  kubeseal -o yaml > my-sealed-secret.yaml

# Fetch certificate (verify controller access)
kubeseal --fetch-cert
```

## Node Operations

### Adding New Nodes

### Controller Node

```bash
cd /home/agentydragon/code/cluster/terraform/infrastructure

# Update terraform.tfvars:
# controller_count = 4
# worker_count = 3

# Apply changes
terraform apply

# New workers/controllers will automatically join the cluster
# Verify with talosctl get members
```

### Node Maintenance

### Restart Single Node

```bash
# Gracefully restart a node (example: controlplane0)
talosctl \
  --endpoints 10.0.1.1 \
  --nodes 10.0.1.1 \
  reboot

# Or force restart via Proxmox
ssh root@atlas 'qm reboot 1500'
```

### Remove Node

```bash
# From Kubernetes perspective
kubectl delete node talos-controlplane0

# Update terraform.tfvars to reduce count, then:
terraform apply
```

## System Diagnostics

### VM Console Management

### Take VM Screenshots

See `~/.claude/skills/proxmox-vm-screenshot/vm-screenshot.sh`

### Direct VM Console Access

```bash
# Interactive console access (from Proxmox host)
ssh root@atlas
qm terminal 1500  # controlplane0
```

## Troubleshooting Common Issues

### Bootstrap Hanging

**Symptoms**: `talosctl bootstrap` times out or hangs
**Solution**: Verify cluster_endpoint points to first controller IP, not VIP:

```hcl
cluster_endpoint = "https://10.0.1.1:6443"  # NOT 10.0.3.1:6443
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
talosctl -n 10.0.2.1 service kubelet restart  # worker0
talosctl -n 10.0.2.2 service kubelet restart  # worker1

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

### PowerDNS DNS Delegation Issues

**Symptoms**: DNS queries fail, cert-manager DNS-01 challenges fail
**Root Causes & Solutions**:

1. **VIP Not Assigned to PowerDNS Service**:
   - **Symptom**: `kubectl get svc powerdns-external` shows `<pending>` for EXTERNAL-IP
   - **Solution**: Check MetalLB configuration and pod status
   - **Fix**: Verify MetalLB speaker pods running, check IPAddressPool config

2. **DNS Delegation Chain Broken**:
   - **Symptom**: `dig @ns1.agentydragon.com test-cluster.agentydragon.com NS` fails
   - **Solution**: Check VPS PowerDNS zone configuration
   - **Fix**: Verify delegation records point to cluster PowerDNS VIP

3. **PowerDNS API Not Accessible**:
   - **Symptom**: cert-manager fails to create DNS-01 challenge records
   - **Solution**: Check PowerDNS pod logs and API service
   - **Fix**: Verify PowerDNS API key secret exists in dns-system namespace

### MetalLB LoadBalancer Issues

**Symptoms**: LoadBalancer services stuck in Pending, no external IP assigned
**Root Causes & Solutions**:

1. **MetalLB Speaker Pods Not Running**:
   - **Symptom**: `kubectl get pods -n metallb-system` shows speaker pods failing
   - **Solution**: Check for CNI issues, node network configuration
   - **Fix**: Restart MetalLB components after resolving network issues

2. **IP Pool Conflicts**:
   - **Symptom**: Some services get IPs while others don't
   - **Solution**: Check IPAddressPool configuration for overlaps
   - **Fix**: Ensure pool ranges don't conflict and specify correct pools in service annotations

3. **L2 Advertisement Issues**:
   - **Symptom**: External IP assigned but not reachable from outside cluster
   - **Solution**: Check L2Advertisement configuration and ARP tables
   - **Fix**: Verify L2Advertisement covers all required IPAddressPools

## Reference Information

### Node IP Assignments

| Node | VM ID | IP Address | Role |
|------|-------|------------|------|
| controlplane0 | 1500 | 10.0.1.1 | Controller |
| controlplane1 | 1501 | 10.0.1.2 | Controller |
| controlplane2 | 1502 | 10.0.1.3 | Controller |
| worker0 | 2000 | 10.0.2.1 | Worker |
| worker1 | 2001 | 10.0.2.2 | Worker |

### VIP Assignments

| Service | IP Address | Pool | Purpose |
|---------|------------|------|---------|
| **Cluster API** | 10.0.3.1 | - | Kubernetes API HA VIP |
| **Ingress** | 10.0.3.2 | ingress-pool | NGINX Ingress LoadBalancer |
| **PowerDNS** | 10.0.3.3 | dns-pool | DNS server LoadBalancer |
| **Services** | 10.0.3.4-20 | services-pool | Harbor, Gitea, etc. |

## Security Configuration

### Privileged Ports (Port < 1024)

Services that need to bind to privileged ports (e.g., DNS on port 53) require the `NET_BIND_SERVICE` capability when
running as non-root user to comply with Pod Security Standards "restricted" policy.

**Example Configuration**:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 953
  runAsGroup: 953
  allowPrivilegeEscalation: false
  capabilities:
    add: ["NET_BIND_SERVICE"]  # Required for ports < 1024
    drop: ["ALL"]
  seccompProfile:
    type: RuntimeDefault
```

**Common Services Requiring This**:

- DNS servers (port 53): PowerDNS, CoreDNS, Unbound
- HTTP servers (port 80): Only when not using LoadBalancer/Ingress
- HTTPS servers (port 443): Only when not using LoadBalancer/Ingress

**Troubleshooting**:

- **Symptom**: Pod stuck in `Init:0/1` or container won't start
- **Check**: `kubectl describe pod <pod-name>` for permission errors
- **Solution**: Add `NET_BIND_SERVICE` capability to container securityContext
