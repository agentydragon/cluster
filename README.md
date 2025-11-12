# Talos Kubernetes Cluster

5-node Talos Kubernetes cluster (3 controllers, 2 workers) with GitOps management and external HTTPS connectivity.

VMs deploy via single `terraform apply` from the `terraform/infrastructure/` directory.

For operational procedures (maintenance, diagnostics, troubleshooting), see <docs/OPERATIONS.md>.

## Development Environment

`.envrc` auto-exports `KUBECONFIG` and `TALOSCONFIG` when entering directory and provides kubeseal, talosctl, fluxcd, helm.
Execute those commands with the direnv loaded, or use `direnv exec .`.

## Cluster State

- VMs run Talos, configured and bootstrapped with Terraform (`terraform/infrastructure/`)
- VMs connected to Headscale mesh (100.64.0.14-18)
- Static IPs -> baked into Image Factory QCOW2 disks together with Tailscale extension + QEMU guest agent
- CNI: Cilium with Talos-specific security configuration
- **VIP high availability**: 10.0.0.20 load-balances across controllers
- **API server networking fix**: BPF hostLegacyRouting for static pod connectivity to worker nodes
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
├── terraform/              # Terraform configurations
│   ├── infrastructure/    # VM infrastructure (Proxmox + Talos) - manual bootstrap
│   │   ├── modules/talos-node/ # Reusable node configuration module
│   │   └── tmp/talos/     # Generated disk images
│   └── gitops/            # SSO service configuration - GitOps managed
│       ├── authentik/     # Authentik provider configuration
│       ├── vault/         # Vault configuration
│       ├── secrets/       # Secret generation
│       └── services/      # Service integration configs
├── k8s/                   # Kubernetes manifests (Flux-managed)
│   ├── infrastructure/    # Core platform services
│   │   ├── core/          # sealed-secrets, tofu-controller
│   │   ├── networking/    # Cilium, cert-manager, ingress-system
│   │   └── platform/      # Vault, Authentik (SSO services)
│   └── applications/      # End-user applications (Gitea, Harbor, Matrix)
├── flux-system/           # Flux controllers (auto-generated)
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

## Prerequisites
- Proxmox host `atlas` with SSH access
- direnv configured in cluster directory
- Internet access for image downloads

## How Things Are Wired Together

### Network Architecture
Internet (443) → `*.test-cluster.agentydragon.com` VPS nginx proxy → Tailscale VPN → Worker NodePort (30443) → NGINX Ingress → Apps

- **VPS**: `~/code/ducktape/ansible/nginx-sites/test-cluster.agentydragon.com.j2`
- **DNS**: `*.test-cluster.agentydragon.com` → VPS IP → PowerDNS with Let's Encrypt DNS-01
- **NodePort**: NGINX Ingress binds to 30080/30443 on worker nodes w0/w1
- **Cilium**: `kubeProxyReplacement: true` with `bindProtection: false` for external NodePort access

- Static IP Bootstrap: Terraform → Image Factory API → Custom QCOW2 with META key 10 → VM boots with static IP (no DHCP)
- GitOps Flow: Git Commit → Flux detects change → Applies K8s manifests → Applications updated
- Deployment path: `k8s/` directory → Flux Kustomizations → HelmReleases → Running pods
- Secret management: local `kubeseal` → sealed-secrets controller → K8s Secret → Application pods

### VIP High Availability
kube-vip leader election → VIP (10.0.0.20) floats between controllers → Load balances API requests

**Bootstrap order**: First controller (10.0.0.11) → Cluster formation → VIP establishment → HA active

## Key File Locations

- **Infrastructure Terraform**: `terraform/infrastructure/` (manual bootstrap)
- **GitOps Terraform**: `terraform/gitops/` (tofu-controller managed)
- **Talos config**: `terraform/infrastructure/talosconfig.yml` (generated, gitignored)
- **Kube config**: `terraform/infrastructure/kubeconfig` (generated, gitignored)
- **Environment**: `.envrc` (direnv)
- **Kubernetes manifests**: `k8s/`
- **VPS nginx config**: `~/code/ducktape/ansible/nginx-sites/`
- **VPS PowerDNS config**: `~/code/ducktape/ansible/host_vars/vps/powerdns.yml`

## External Dependencies

- **Proxmox host**: `atlas` at 10.0.0.5 for VM hosting
- **VPS**: nginx proxy and PowerDNS for external connectivity
- **GitHub**: Repository hosting and Flux source
