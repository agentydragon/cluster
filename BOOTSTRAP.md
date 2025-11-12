# Talos Cluster Bootstrap Playbook

This document provides step-by-step instructions for cold-starting the Talos cluster from nothing and managing individual nodes.

## Cold-Start Cluster Deployment

### Prerequisites
- Proxmox host (`atlas`) accessible via SSH
- Ansible vault configured with API tokens
- `direnv` configured in cluster directory

### Step 1: Fully Declarative Deployment
```bash
cd terraform
./tf.sh apply
```

This handles:
- QCOW2 disk image from Talos Image Factory with baked-in static IP configuration
- VM creation with pre-configured networking
- Talos machine configuration application
- Kubernetes cluster initialization and bootstrap

### Step 2: Verify Deployment Success
```bash
# All VMs should be running with correct static IPs
for ip in 10.0.0.{11..13} 10.0.0.{21..22}; do ping -c1 $ip; done

# ✅ VIP should be active immediately after terraform completes
ping 10.0.0.20  # VIP (load balancer)
```

### Step 3: Install CNI (Required for Node Ready Status)
```bash
# Navigate to cluster root (KUBECONFIG automatically set via .envrc)
cd /home/agentydragon/code/cluster

# Add Cilium repository
helm repo add cilium https://helm.cilium.io/
helm repo update

# Install Cilium with Talos-specific configuration
helm install cilium cilium/cilium --namespace kube-system --version 1.16.5 \
  --set cluster.name=talos-cluster \
  --set cluster.id=1 \
  --set k8sServiceHost=10.0.0.11 \
  --set k8sServicePort=6443 \
  --set ipam.mode=kubernetes \
  --set securityContext.capabilities.ciliumAgent='{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}' \
  --set securityContext.capabilities.cleanCiliumState='{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}' \
  --set cgroup.hostRoot=/sys/fs/cgroup \
  --set cgroup.autoMount.enabled=false
```

### Step 4: Verify Full Cluster Health
```bash
# ✅ All nodes should show Ready status
kubectl get nodes -o wide

# ✅ Test VIP functionality
kubectl --server=https://10.0.0.20:6443 get nodes

# ✅ Verify Cilium pods are running
kubectl get pods -n kube-system -l k8s-app=cilium
```

## Adding New Nodes

### Controller Node
```bash
cd /home/agentydragon/code/cluster/terraform

# Update terraform.tfvars:
# controller_count = 4  # or desired count

# Apply changes
./tf.sh apply

# New controller will automatically join the cluster
# Verify with talosctl get members
```

### Worker Node  
```bash
cd /home/agentydragon/code/cluster/terraform

# Update terraform.tfvars:
# worker_count = 3  # or desired count

# Apply changes
./tf.sh apply

# New worker will automatically join
# Verify with kubectl get nodes
```

## Node Maintenance

### Restart Single Node
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

### Remove Node
```bash
# From Kubernetes perspective
kubectl delete node talos-controller-1

# Update terraform.tfvars to reduce count, then:
./tf.sh apply
```

## VM Console Management

### Take VM Screenshots

See `~/.claude/skills/proxmox-vm-screenshot/vm-screenshot.sh`

### Direct VM Console Access
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

## Key File Locations

- **Terraform configs**: `/home/agentydragon/code/cluster/terraform/`
- **Talos config**: `terraform/talosconfig.yml` (generated, gitignored)
- **Kube config**: `terraform/kubeconfig` (generated, gitignored)
- **Environment**: `/home/agentydragon/code/cluster/.envrc` (direnv)

## Node IP Assignments

| Node | VM ID | IP Address | Role |
|------|-------|------------|------|
| controller-1 | 106 | 10.0.0.11 | Controller |
| controller-2 | 107 | 10.0.0.12 | Controller |
| controller-3 | 108 | 10.0.0.13 | Controller |
| worker-1 | 109 | 10.0.0.21 | Worker |
| worker-2 | 110 | 10.0.0.22 | Worker |
| **VIP** | - | 10.0.0.20 | Load Balancer |

## Current Cluster Status

**Production-ready cluster operational**

**Infrastructure**:
- 5-node Talos cluster (3 controllers + 2 workers)
- Static IP networking with VIP load balancing (10.0.0.20)
- Tailscale mesh connectivity across all nodes

**Platform Services**:  
- Cilium v1.16.5 CNI with kube-proxy replacement and BPF hostLegacyRouting
- NGINX Ingress Controller HA (2 replicas, NodePort 30080/30443)
- cert-manager for SSL certificate automation
- sealed-secrets controller for encrypted secrets in Git (kubeseal v0.32.2)
- Flux GitOps managing all applications declaratively

**External Connectivity**:
- VPS nginx proxy with Let's Encrypt SSL termination
- Complete HTTPS chain: Internet → VPS → Tailscale → NodePort → Applications  
- Live test application: https://test.test-cluster.agentydragon.com/

**Security & Secret Management**:
- sealed-secrets controller running in kube-system namespace
- kubeseal v0.32.2 with conventional functionality (no hacks required)
- Certificate fetch and sealing operations working with default service discovery
- Environment configured via shell.nix for latest kubeseal from nixpkgs-unstable

**Development Environment**:
- direnv configuration with nix shell for consistent tool versions
- TALOSCONFIG and KUBECONFIG automatically set in cluster directory
- kubeseal, talosctl, and fluxcd available via nix-provided packages

**Next Steps** (Optional Enhancements):
1. **Install Platform Services**: Vault, Authentik, Harbor, Gitea via GitOps
2. **Configure Backup**: Set up etcd backup and restore procedures  
3. **Monitor Setup**: Deploy monitoring and observability stack
4. **Security Hardening**: Apply network policies via Cilium
5. **PowerDNS Zone Automation**: Implement proper zone management in Ansible

## Step 5: Configure External Connectivity via VPS Proxy

### Prerequisites
- VPS with nginx and PowerDNS already configured via Ansible
- Access to AWS Route 53 for `agentydragon.com` domain delegation

### DNS Delegation Setup (Required)

**Critical**: You must create NS delegation records in your domain registrar/DNS provider:

1. **In AWS Route 53** (for `agentydragon.com`):
   ```
   Record Name: test-cluster.agentydragon.com
   Record Type: NS  
   Record Value: ns1.agentydragon.com
   TTL: 3600
   ```

2. **Why this is needed**:
   - Let's Encrypt validates DNS TXT records via public DNS queries
   - Without NS delegation, Let's Encrypt queries AWS Route 53, which doesn't know about the subdomain
   - With delegation, Let's Encrypt queries your PowerDNS server where the TXT records are created

### PowerDNS Zone Configuration

Add the new domain to your Ansible PowerDNS configuration:

```yaml
# In host_vars/vps/powerdns.yml
powerdns_domains:
  - name: "test-cluster.agentydragon.com"
    type: "NATIVE"
    records:
      - name: "@"
        type: "SOA"
        content: "ns1.agentydragon.com. hostmaster.agentydragon.com. 2025111000 3600 1800 604800 300"
        ttl: 300
      - name: "@"
        type: "NS"
        content: "ns1.agentydragon.com."
        ttl: 300
      - name: "*"
        type: "A"
        content: "172.235.48.86"  # VPS internal IP for proxy
        ttl: 300
```

### Let's Encrypt Certificate Configuration

Add Let's Encrypt task to VPS playbook:

```yaml
# In vps.yaml
- name: "Let's Encrypt | *.test-cluster.agentydragon.com (wildcard)"
  ansible.builtin.import_role:
    name: letsencrypt-dns
  vars:
    letsencrypt_dns_cert_name: "test-cluster-wildcard"
    letsencrypt_dns_domains:
      - "*.test-cluster.agentydragon.com"
    letsencrypt_dns_provider: "powerdns"
  tags: [letsencrypt, test-cluster-wildcard]
```

### Nginx Proxy Configuration

Create nginx site template at `/home/agentydragon/code/ducktape/ansible/nginx-sites/test-cluster.agentydragon.com.j2` with wildcard proxy configuration for `*.test-cluster.agentydragon.com` → `w0:30443` via Tailscale.

### Deploy External Connectivity

```bash
# From your Ansible directory
cd /home/agentydragon/code/ducktape/ansible

# Deploy PowerDNS zones and nginx configuration
ansible-playbook vps.yaml -t powerdns,nginx-sites

# Create Let's Encrypt certificates
ansible-playbook vps.yaml -t test-cluster-wildcard
```

### Configure Cluster Ingress Controller

The cluster needs an ingress controller configured with NodePort access:

```yaml
# apps/ingress-nginx/helmrelease.yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: ingress-nginx
  namespace: ingress-nginx
spec:
  values:
    controller:
      # Use NodePort for external access
      service:
        type: NodePort
        nodePorts:
          http: 30080
          https: 30443
      
      # Configure as default ingress class
      ingressClassResource:
        name: nginx
        enabled: true
        default: true
```

**Key Configuration Notes**:
- **Cilium kube-proxy replacement**: Must be enabled (`kubeProxyReplacement: "true"`)
- **NodePort bindProtection**: Must be disabled (`nodePort.bindProtection: false`)
- **External access**: VPS connects via Tailscale to worker nodes on NodePort 30443

### Test External Connectivity

```bash
# Test DNS resolution
dig foo.test-cluster.agentydragon.com
# Should resolve to: 172.235.48.86 (VPS IP)

# ✅ Test HTTPS connectivity - WORKING!
curl https://test.test-cluster.agentydragon.com/
# Returns: HTTP/2 200 - Test application shows infrastructure details
```

**Current Status**: End-to-end connectivity operational
- VPS nginx proxy → Tailscale VPN → NodePort 30443 → NGINX Ingress → Applications
- Live test: https://test.test-cluster.agentydragon.com/ serving test application

### Deploy Applications with Ingress

Applications are deployed via GitOps in the `k8s/applications/` directory. The existing test application demonstrates the pattern:
- **Committed**: `k8s/applications/test-app/` (deployment, service, ingress, configmap)
- **Accessible**: https://test.test-cluster.agentydragon.com/

**Result**: Applications become automatically accessible at `https://app-name.test-cluster.agentydragon.com/`

## Step 6: GitOps with Flux

**Operational**: Flux GitOps is managing the cluster via GitHub repository `agentydragon/cluster`.

**Current GitOps Status**:
- Flux controllers are running and healthy
- Repository: `https://github.com/agentydragon/cluster` 
- Auto-sync enabled for all applications in `apps/` directory
- **Deployed Applications**:
  - **Cilium CNI**: `/apps/cilium/` - Network fabric and security
  - **NGINX Ingress**: `/apps/ingress-system/` - HA deployment with NodePort
  - **cert-manager**: `/apps/cert-manager/` - SSL certificate automation
  - **Test Application**: `/apps/test-app/` - Validates end-to-end connectivity

### Migrate Cilium to GitOps (Optional)
```bash
# Export current Cilium values for GitOps
helm get values cilium -n kube-system > apps/cilium/values.yaml

# Create HelmRelease manifest (see PLAN.md for details)
# Commit and push - Flux will adopt existing Helm installation
```

### Future Deployments
After Flux setup, deploy changes by committing and pushing to GitHub.
Changes are deployed automatically by Flux controller within ~1 minute.
