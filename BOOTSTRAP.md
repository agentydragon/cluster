# Talos Cluster Bootstrap Playbook

This document provides step-by-step instructions for cold-starting the Talos cluster from nothing and managing individual nodes.

## Cold-Start Cluster Deployment

### Prerequisites
- Proxmox host (`atlas`) accessible via SSH
- Ansible vault configured with API tokens
- `direnv` configured in cluster directory
- VPS with nginx and PowerDNS already configured via Ansible
- Access to AWS Route 53 for `agentydragon.com` domain delegation

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

#### Test
```bash
# All VMs should be running with correct static IPs
for ip in 10.0.0.{11..13} 10.0.0.{21..22}; do ping -c1 $ip; done

# VIP should be active
ping 10.0.0.20  # VIP (load balancer)
```

### Step 2: Install CNI (Required for Node Ready Status)
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

#### Test
```bash
# All nodes should show Ready status
kubectl get nodes -o wide

# Test VIP
kubectl --server=https://10.0.0.20:6443 get nodes

# Verify Cilium pods are running
kubectl get pods -n kube-system -l k8s-app=cilium
```

### Step 3: External Connectivity via VPS

#### Step 3.1: DNS Delegation

Create NS delegation records in Route 53 to allow Let's Encrypt DNS-01 validation for `test-cluster.agentydragon.com` via PowerDNS on the VPS:
```
Record Name: test-cluster.agentydragon.com
Record Type: NS  
Record Value: ns1.agentydragon.com
TTL: 3600
```

#### Step 3.2: PowerDNS configuration

Add `test-cluster.agentydragon.com` domain configuration to `~/code/ducktape/ansible/host_vars/vps/powerdns.yml` with SOA, NS, and wildcard A records pointing to VPS IP.

#### Step 3.3: Let's Encrypt task

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

#### Step 3.4: NGINX Proxy Site Configuration

Create nginx site template at `~/code/ducktape/ansible/nginx-sites/test-cluster.agentydragon.com.j2` with wildcard proxy configuration for `*.test-cluster.agentydragon.com` → `w0:30443` via Tailscale.

#### Step 3.5: Deploy VPS configuration

Deploy:
```bash
# From your Ansible directory
cd ~/code/ducktape/ansible

# Deploy PowerDNS zones and nginx configuration
ansible-playbook vps.yaml -t powerdns,nginx-sites

# Create Let's Encrypt certificates
ansible-playbook vps.yaml -t test-cluster-wildcard
```

### Configure Cluster Ingress Controller

NGINX Ingress Controller is deployed via GitOps with NodePort configuration (30080/30443) for external VPS proxy access via Tailscale.

#### Test

```bash
dig foo.test-cluster.agentydragon.com  # Should resolve to: 172.235.48.86 (VPS IP)
curl https://test.test-cluster.agentydragon.com/ # Should return HTTP/2 200
```

### Step 4: Setup GitOps with Flux

Bootstrap Flux to manage the cluster via this GitHub repository:

```bash
cd /home/agentydragon/code/cluster

# Bootstrap Flux (requires GitHub personal access token)
flux bootstrap github \
  --owner=agentydragon \
  --repository=cluster \
  --path=k8s \
  --personal \
  --read-write-key
```

This command:
- Installs Flux controllers in `flux-system` namespace
- Creates deploy key in GitHub repository 
- Sets up GitOps automation for `k8s/` directory
- Deploys all infrastructure and applications automatically

#### Test GitOps
```bash
# Verify Flux controllers are running
kubectl get pods -n flux-system

# Check GitOps status
flux get all

# Verify applications are deployed
kubectl get pods -A
```

Once Flux is operational, all infrastructure changes are managed via Git commits to this repository.
