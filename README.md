# Talos Kubernetes Cluster

Production-ready 5-node Talos Kubernetes cluster with GitOps management and external HTTPS connectivity.

## Current Cluster State

### Infrastructure
- **5-node Talos cluster**: 3 controllers (10.0.0.11-13) + 2 workers (10.0.0.21-22)
- **High availability**: VIP load balancer at 10.0.0.20 across controllers
- **Static IP networking**: QCOW2 disk images with baked-in network configuration (no DHCP)
- **Tailscale integration**: All nodes connected via VPN mesh
- **Single-command deployment**: Complete cluster via `terraform apply`

### Platform Services
- **Cilium v1.16.5**: CNI with kube-proxy replacement and BPF hostLegacyRouting
- **NGINX Ingress**: HA deployment (2 replicas on workers, NodePort 30080/30443)
- **cert-manager**: Automatic SSL certificate management
- **sealed-secrets**: Encrypted secrets in Git (kubeseal v0.32.2)
- **Flux GitOps**: Declarative cluster management from this repository

### External Connectivity
- **Domain**: `*.test-cluster.agentydragon.com` 
- **HTTPS chain**: Internet → VPS nginx proxy → Tailscale VPN → NodePort → NGINX Ingress → Applications
- **SSL termination**: Let's Encrypt wildcard certificates on VPS
- **Live test**: https://test.test-cluster.agentydragon.com/

## Repository Structure

```
cluster/
├── terraform/              # VM infrastructure (Proxmox + Talos)
├── k8s/                    # Kubernetes manifests (Flux-managed)
│   ├── infrastructure/     # Core services (Cilium, cert-manager, sealed-secrets)
│   ├── apps/              # Applications and test services
│   └── flux-system/       # Flux controllers (auto-generated)
├── shell.nix              # Nix development environment
├── .envrc                 # direnv configuration (KUBECONFIG, TALOSCONFIG)
├── BOOTSTRAP.md           # Complete deployment procedures
├── PLAN.md               # Project roadmap and completed features
└── AGENTS.md             # Documentation strategy for Claude Code
```

## Quick Start

### Prerequisites
- Proxmox host `atlas` with SSH access
- direnv configured in cluster directory
- Internet access for image downloads

### Deploy Complete Cluster
```bash
cd /home/agentydragon/code/cluster/terraform
./tf.sh apply
```

This single command:
- Creates 5 VMs with static IP configuration
- Bootstraps complete Kubernetes cluster
- Configures VIP high availability

### Access Cluster
```bash
cd /home/agentydragon/code/cluster
# KUBECONFIG automatically set via .envrc
kubectl get nodes -o wide

# Use VIP for high availability
kubectl --server=https://10.0.0.20:6443 get nodes
```

## Routine Maintenance

### Node Operations
```bash
# Restart node (graceful)
direnv exec . talosctl -n 10.0.0.21 reboot

# View node status
direnv exec . talosctl -n 10.0.0.11,10.0.0.12,10.0.0.13 version

# Check kubelet issues (common after restarts)
direnv exec . talosctl -n 10.0.0.21 service kubelet restart
```

### Application Management
```bash
# Check Flux status
direnv exec . flux get all

# Force reconciliation
direnv exec . flux reconcile helmrelease sealed-secrets

# Check specific application
kubectl get all -n kube-system -l app.kubernetes.io/name=sealed-secrets
```

### Secret Management
```bash
# Create sealed secret
kubectl create secret generic my-secret --from-literal=key=value --dry-run=client -o yaml | \
  direnv exec . kubeseal -o yaml > my-sealed-secret.yaml

# Fetch certificate (verify controller access)
direnv exec . kubeseal --fetch-cert
```

### Cluster Scaling
```bash
# Add worker node
cd terraform/
# Edit terraform.tfvars: worker_count = 3
./tf.sh apply

# Remove node
kubectl delete node talos-worker-3
# Edit terraform.tfvars: worker_count = 2
./tf.sh apply
```

## How Things Are Wired Together

### Network Architecture
```
Internet (443) → VPS nginx proxy → Tailscale VPN → Worker NodePort (30443) → NGINX Ingress → Apps
```

**Key Configuration**:
- **VPS**: `/home/agentydragon/code/ducktape/ansible/nginx-sites/test-cluster.agentydragon.com.j2`
- **DNS**: `*.test-cluster.agentydragon.com` → VPS IP → PowerDNS with Let's Encrypt DNS-01
- **NodePort**: NGINX Ingress binds to 30080/30443 on worker nodes w0/w1
- **Cilium**: `kubeProxyReplacement: true` with `bindProtection: false` for external NodePort access

### GitOps Flow
```
Git Commit → Flux detects change → Applies K8s manifests → Applications updated
```

**Deployment Path**: `k8s/` directory → Flux Kustomizations → HelmReleases → Running pods

### Secret Management
```
Local kubeseal → sealed-secrets controller → K8s Secret → Application pods
```

**Encryption**: Public key in controller, private key sealed in etcd, secrets decrypted at runtime

### Static IP Bootstrap
```
Terraform → Image Factory API → Custom QCOW2 with META key 10 → VM boots with static IP
```

**No DHCP**: Network configuration baked into disk image, VMs boot directly to predetermined IPs

### VIP High Availability
```
kube-vip leader election → VIP (10.0.0.20) floats between controllers → Load balances API requests
```

**Bootstrap order**: First controller (10.0.0.11) → Cluster formation → VIP establishment → HA active

## Troubleshooting Common Issues

### Nodes NotReady
Usually kubelet services stuck after restart:
```bash
direnv exec . talosctl -n 10.0.0.21 service kubelet restart
```

### Ingress Not Accessible
Check NodePort binding and Cilium configuration:
```bash
kubectl get svc -n ingress-system
# Should show NodePort 30080:30080/TCP,443:30443/TCP

kubectl get pods -n ingress-system -o wide
# Should show pods running on worker nodes w0/w1
```

### Sealed Secrets Failing
Verify controller and service discovery:
```bash
kubectl get all -n kube-system | grep sealed
direnv exec . kubeseal --fetch-cert  # Should return certificate
```

### GitOps Not Reconciling
Check Flux status and force reconciliation:
```bash
direnv exec . flux get all
direnv exec . flux reconcile source git cluster
```

## External Dependencies

- **Proxmox host**: `atlas` at 10.0.0.5 for VM hosting
- **VPS**: nginx proxy and PowerDNS for external connectivity  
- **Domain**: `agentydragon.com` with NS delegation to `ns1.agentydragon.com`
- **Tailscale**: VPN mesh for VPS → cluster connectivity
- **GitHub**: Repository hosting and Flux source

## Development Environment

Uses Nix + direnv for consistent tool versions:
- **shell.nix**: kubeseal v0.32.2, talosctl, fluxcd from nixpkgs-unstable
- **.envrc**: Auto-exports KUBECONFIG and TALOSCONFIG when entering directory
- **Version consistency**: All tools from nix store, no system dependencies