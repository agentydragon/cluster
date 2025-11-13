# Talos Kubernetes Cluster

Small Talos k8s cluster with GitOps and HTTPS.

- Deploy: single `terraform apply` in `terraform/infrastructure/`.
- VMs:
  - Run Talos, configured and bootstrapped with Terraform (`terraform/infrastructure/`).
  - Disks are pre-baked per-node from Image Factory with static IPs and Tailscale + QEMU guest agent
- VPS forwards traffic to cluster through Tailscale mesh.
- Test application: <https://test.test-cluster.agentydragon.com/>
- CNI: Cilium with Talos-specific security configuration

## direnv

`.envrc` auto-exports `KUBECONFIG` and `TALOSCONFIG` and provides CLI tools (kubeseal, talosctl, etc.).
Execute tools like these with the direnv loaded, or use `direnv exec .`.

## Infrastructure

- Network: 10.0.0.0/16, gateway 10.0.0.1
- 5 Talos nodes:
  - 3 controllers (controlplane0-2 = 10.0.1.1-3)
  - 2 workers (worker0-1 = 10.0.2.1-2)
- High availability VIP pools:
  - 10.0.3.1: Cluster Kube API endpoint - kube-vip LB across controller Kube API servers
  - 10.0.3.2 (`ingress-pool`): MetalLB across worker node replicas of NGINX Ingress
  - 10.0.3.3 (`dns-pool`): PowerDNS
  - 10.0.3.4-20 (`services-pool`): for future use (Harbor, Gitea, etc.)
- Domain: `*.test-cluster.agentydragon.com`
  - PowerDNS in k8s has authority on this domain and handles Let's Encrypt DNS-01 challenges
  - cert-manager provisions Let's Encrypt certs
- HTTPS chain: Internet → VPS nginx reads CNI → Tailscale VPN → HA VIP → NGINX Ingress terminates TLS → app

## Repository Structure

```text
cluster/
├── shell.nix, .envrc      # direnv (KUBECONFIG, TALOSCONFIG, kubeseal CLI, ...)
├── docs/
│   ├── BOOTSTRAP.md       # Bootstrap procedure from empty Proxmox
│   ├── OPERATIONS.md      # Management, troubleshooting commands
│   └── PLAN.md            # Future roadmap, strategic decisions
├── CLAUDE.md, AGENTS.md   # Instructions for AI agents
├── terraform/
│   ├── infrastructure/    # Provisioning from empty Proxmox; boots Talos, Kube, Cilium; hands off to Flux
│   │   ├── talosconfig    # Creds for node Talos APIs (generated, gitignored)
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

## How Things Are Wired Together

### Network Architecture

Internet (443) → VPS nginx proxy → Tailscale VPN → MetalLB VIP (10.0.3.2:443) → NGINX Ingress → Apps

- VPS: `~/code/ducktape/ansible/nginx-sites/test-cluster.agentydragon.com.j2`
- DNS:
  - VPS PowerDNS delegates `test-cluster.agentydragon.com` → cluster PowerDNS (10.0.3.3)
  - Cluster PowerDNS handles Let's Encrypt DNS-01 challenges to obtain SSL certs
- LoadBalancer: NGINX Ingress uses MetalLB VIP 10.0.3.2 instead of NodePort
- Cilium: `kubeProxyReplacement: true` with privileged port protection enabled

- Terraform → Image Factory API → Custom QCOW2 with META key 10 → VMs with static IPs (no DHCP)
- GitOps flow: Git commit → Flux detects change → applies k8s manifests
- Deployment path: `k8s/` directory → Flux Kustomizations → HelmReleases → Running pods
- Secret management: local `kubeseal` → sealed-secrets controller → K8s Secret → Application pods

Kube VIP (10.0.3.1) is established after cluster formation, so bootstrap instead runs against first controller (10.0.1.1).

## Prerequisites / external dependencies

- direnv configured in cluster directory
- VM hosting: Proxmox host `atlas` with SSH access
- GitHub for Flux
- VPS: nginx proxy and PowerDNS for external connectivity, configured in `~/code/ducktape` repo:
  - nginx: `ansible/nginx-sites/`
  - PowerDNS: `ansible/host_vars/vps/powerdns.yml`
