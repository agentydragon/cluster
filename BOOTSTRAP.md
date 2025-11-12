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

Add `test-cluster.agentydragon.com` domain configuration to `/home/agentydragon/code/ducktape/ansible/host_vars/vps/powerdns.yml` with SOA, NS, and wildcard A records pointing to VPS IP.

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

NGINX Ingress Controller is deployed via GitOps with NodePort configuration (30080/30443) for external VPS proxy access via Tailscale.

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
