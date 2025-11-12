# Talos Kubernetes Cluster

5-node Talos Kubernetes cluster (3 controllers, 2 workers) with GitOps management and external HTTPS connectivity.

VMs deploy via single `terraform apply`.

## Cluster State

- CNI: Cilium with Talos-specific security configuration
- Static IPs -> baked into Image Factory QCOW2 images together with Tailscale extension + QEMU guest agent
- **VIP high availability**: 10.0.0.20 load-balances across controllers  
- **Image Factory Integration**: VMs created with QCOW2 disk images containing baked-in static IP configuration
- **Talos machine configurations applied**: All nodes configured via Terraform
- **Bootstrap endpoint fix**: Changed from VIP to first controller to resolve chicken-and-egg
- **Automated bootstrap execution**: Complete cluster initialization via terraform
- **CNI Installation**: Cilium v1.16.5 CNI installed with Talos-specific configuration
- **API server networking fix**: BPF hostLegacyRouting for static pod connectivity to worker nodes
- **Tailscale connectivity**: All nodes connected to headscale mesh (100.64.0.14-18)
- **Platform services**: Cilium CNI, cert-manager, ingress-nginx deployed via GitOps
- **External HTTPS connectivity**: Complete VPS proxy → Tailscale → cluster ingress chain
- **NGINX Ingress HA**: 2 replicas on worker nodes with NodePort 30080/30443
- **End-to-end testing**: Test application accessible via https://test.test-cluster.agentydragon.com/

### Infrastructure
- **5-node Talos cluster**: 3 controllers (10.0.0.11-13) + 2 workers (10.0.0.21-22)
- **Controllers**: `10.0.0.11`, `10.0.0.12`, `10.0.0.13` (c0, c1, c2)
- **Workers**: `10.0.0.21`, `10.0.0.22` (w0, w1)
- **Cluster VIP**: `10.0.0.20` (load balancer across controllers)
- **Network**: All nodes on 10.0.0.0/16 with gateway 10.0.0.1

### Platform Services
- **Cilium v1.16.5**: CNI with kube-proxy replacement and BPF hostLegacyRouting
- **NGINX Ingress**: HA deployment (2 replicas on workers, NodePort 30080/30443)
- **cert-manager**: Automatic SSL certificate management
- **sealed-secrets**: Encrypted secrets in Git (kubeseal v0.32.2)
- **Flux GitOps**: Declarative cluster management from this repository

### Key Implementation Details
- **Image Factory**: QCOW2 disk images with META key 10 static IP configuration
- **Terraform Modules**: Clean per-node architecture with unified configuration
- **Bootstrap Automation**: Single `terraform apply` handles everything
- **Extension Integration**: Tailscale + QEMU agent via Image Factory schematics
- **VIP Management**: Automatic kube-vip deployment for high availability

### External Connectivity
- **Domain**: `*.test-cluster.agentydragon.com` 
- **HTTPS chain**: Internet → VPS nginx proxy → Tailscale VPN → NodePort → NGINX Ingress → Applications
- **SSL termination**: Let's Encrypt wildcard certificates on VPS
- **Live test**: https://test.test-cluster.agentydragon.com/

## Repository Structure

```
cluster/
├── terraform/              # VM infrastructure (Proxmox + Talos)
│   ├── modules/talos-node/ # Reusable node configuration module
│   └── tmp/talos/         # Generated disk images
├── k8s/                   # Kubernetes manifests (Flux-managed)
│   ├── infrastructure/    # Core platform services
│   │   ├── core/          # sealed-secrets, tofu-controller
│   │   ├── networking/    # Cilium, cert-manager, ingress-system
│   │   └── platform/      # Vault, Authentik (SSO services)
│   └── applications/      # End-user applications (Gitea, Harbor, Matrix)
├── flux-system/           # Flux controllers (auto-generated)
├── sso-terraform/         # Terraform for SSO service configuration
├── bootstrap-secrets/     # Bootstrap secret templates
├── scripts/               # Utility scripts
├── shell.nix             # Nix development environment
├── .envrc                # direnv configuration (KUBECONFIG, TALOSCONFIG)
├── docs/
│   ├── BOOTSTRAP.md      # Complete deployment procedures
│   ├── OPERATIONS.md     # Day-to-day cluster management
│   └── PLAN.md          # Project roadmap and strategic decisions
└── AGENTS.md            # Documentation strategy for Claude Code
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

For all operational procedures including scaling, maintenance, diagnostics, and troubleshooting, see **docs/OPERATIONS.md**.

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
talosctl -n 10.0.0.21 service kubelet restart
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
kubeseal --fetch-cert  # Should return certificate
```

### GitOps Not Reconciling
Check Flux status and force reconciliation:
```bash
flux get all
flux reconcile source git cluster
```

## Key File Locations

- **Terraform configs**: `/home/agentydragon/code/cluster/terraform/`
- **Talos config**: `terraform/talosconfig.yml` (generated, gitignored)
- **Kube config**: `terraform/kubeconfig` (generated, gitignored)
- **Environment**: `/home/agentydragon/code/cluster/.envrc` (direnv)
- **Kubernetes manifests**: `/home/agentydragon/code/cluster/k8s/`
- **VPS nginx config**: `/home/agentydragon/code/ducktape/ansible/nginx-sites/`
- **VPS PowerDNS config**: `/home/agentydragon/code/ducktape/ansible/host_vars/vps/powerdns.yml`

## External Dependencies

- **Proxmox host**: `atlas` at 10.0.0.5 for VM hosting
- **VPS**: nginx proxy and PowerDNS for external connectivity  
- **Domain**: `agentydragon.com` with NS delegation to `ns1.agentydragon.com`
- **Tailscale**: VPN mesh for VPS → cluster connectivity
- **GitHub**: Repository hosting and Flux source

## Development Environment

Uses Nix + direnv for consistent tool versions:
- **shell.nix**: kubeseal v0.32.2, talosctl, fluxcd, helm from nixpkgs-unstable
- **.envrc**: Auto-exports KUBECONFIG and TALOSCONFIG when entering directory
- **Version consistency**: All tools from nix store, no system dependencies

**Command Execution**: All kubectl, talosctl, kubeseal, flux, and helm commands assume execution from cluster directory (direnv auto-loaded) or using `direnv exec .` prefix if run elsewhere.
