# Talos Kubernetes Cluster

5-node Talos Kubernetes cluster (3 controllers, 2 workers) with GitOps management and external HTTPS connectivity.
VMs deploy via single `terraform apply` from the `terraform/infrastructure/` directory.

For operational procedures (maintenance, diagnostics, troubleshooting), see <docs/OPERATIONS.md>.

## Development Environment

`.envrc` auto-exports `KUBECONFIG` and `TALOSCONFIG` when entering directory and provides kubeseal, talosctl, fluxcd, helm.
Execute those commands with the direnv loaded, or use `direnv exec .`.

## Cluster State

- VMs run Talos, configured and bootstrapped with Terraform (`terraform/infrastructure/`)
- VMs connected to Headscale mesh
- Pre-baked per-node Image Factory disks with static IPs and Tailscale + QEMU guest agent extensions
- CNI: Cilium with Talos-specific security configuration (with kube-proxy replacement and BPF hostLegacyRouting)
- **API server networking fix**: BPF hostLegacyRouting for static pod connectivity to worker nodes
- External HTTPS connectivity: VPS proxy → Tailscale → cluster ingress chain
- Test application: <https://test.test-cluster.agentydragon.com/>

### Infrastructure

- Network: 10.0.0.0/16, gateway 10.0.0.1
- 5 Talos nodes:
  - 3 controllers (controlplane0-2 = 10.0.1.1-3)
  - 2 workers (worker0-1 = 10.0.2.1-2)
- High availability VIP pools:
  - 10.0.3.1: kube-vip LB across controller Kube API servers
  - 10.0.3.2 (`ingress-pool`): MetalLB across worker node replicas of NGINX Ingress
  - 10.0.3.3 (`dns-pool`): PowerDNS
  - 10.0.3.4-20 (`services-pool`): for future use (Harbor, Gitea, etc.)

### Platform Services

- **NGINX Ingress**: HA deployment (2 replicas on workers, MetalLB LoadBalancer 10.0.3.2)
- **PowerDNS**: Authoritative DNS server with API (MetalLB LoadBalancer 10.0.3.3)
- **cert-manager**: Automatic SSL certificate management with PowerDNS DNS-01 challenges
- **sealed-secrets**: Encrypted secrets in Git
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
- **Live test**: <https://test.test-cluster.agentydragon.com/>

## Repository Structure

```text
cluster/
├── shell.nix, .envrc      # direnv (KUBECONFIG, TALOSCONFIG, kubeseal CLI, ...)
├── docs/
│   ├── BOOTSTRAP.md       # Procedure to bootstrap from empty Proxmox
│   ├── OPERATIONS.md      # Commands for management, troubleshooting
│   └── PLAN.md            # Future roadmap, strategic decisions
├── CLAUDE.md, AGENTS.md   # Instructions for AI agents
├── terraform/
│   ├── infrastructure/    # Basic cluster infra (Proxmox, Talos, Cilium, Flux), manually applied
│   │   ├── talosconfig    # Talos configuration to access node Talos APIs (generated, gitignored)
│   │   ├── kubeconfig     # Kube config (generated, gitignored)
│   │   ├── modules/talos-node/ # Reusable Talos node module
│   │   └── tmp/           # Temporary files (e.g., per-node baked Talos disk images)
│   └── gitops/            # tofu-controller managed Terraform
│       ├── authentik/     # Authentik SSO provider configuration
│       ├── vault/         # Vault configuration
│       ├── secrets/       # Secret generation
│       └── services/      # Service integration configs
├── k8s/                   # Kubernetes manifests (Flux-managed)
│   ├── core/              # CRDs and controllers (sealed-secrets, tofu-controller)
│   ├── cilium/            # CNI networking
│   ├── metallb/           # Load balancer
│   ├── cert-manager/
│   ├── ingress-nginx/     # HTTP(S) ingress
│   ├── powerdns/          # DNS server (external)
│   ├── vault/, external-secrets/  # Secret synchronization
│   ├── authentik/         # Identity and SSO provider
│   ├── services-config/   # Authentik SSO config for services, via Terraform
│   └── applications/
│       ├── harbor/        # Container registry
│       └── gitea/, matrix/, test-app/
└── flux-system/           # Flux controllers (auto-generated)
```

## Prerequisites

- Proxmox host `atlas` with SSH access
- direnv configured in cluster directory
- Internet access for image downloads

## How Things Are Wired Together

### Network Architecture

Internet (443) → VPS nginx proxy → Tailscale VPN → MetalLB VIP (10.0.3.2:443) → NGINX Ingress → Apps

- VPS: `~/code/ducktape/ansible/nginx-sites/test-cluster.agentydragon.com.j2`
- DNS:
  - VPS PowerDNS delegates `test-cluster.agentydragon.com` → cluster PowerDNS (10.0.3.3)
  - In-cluster PowerDNS handles Let's Encrypt DNS-01 challenges to obtain SSL certs
- LoadBalancer: NGINX Ingress uses MetalLB VIP 10.0.3.2 instead of NodePort
- Cilium: `kubeProxyReplacement: true` with privileged port protection enabled

- Terraform → Image Factory API → Custom QCOW2 with META key 10 → VMs with static IPs (no DHCP)
- GitOps Flow: Git commit → Flux detects change → applies k8s manifests
- Deployment path: `k8s/` directory → Flux Kustomizations → HelmReleases → Running pods
- Secret management: local `kubeseal` → sealed-secrets controller → K8s Secret → Application pods

### VIP High Availability

kube-vip leader election → VIP (10.0.3.1) floats between controllers → Load balances API requests

Bootstrap order: First controller (10.0.1.1) → Cluster formation → VIP establishment → HA active

## External dependencies

- ssh access to Proxmox host `atlas` for VM hosting
- GitHub for Flux
- VPS: nginx proxy and PowerDNS for external connectivity, configured in `~/code/ducktape` repo:
  - nginx: `ansible/nginx-sites/`
  - PowerDNS: `ansible/host_vars/vps/powerdns.yml`
