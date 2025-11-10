# Home Proxmox → Talos Cluster Plan

This document tracks how to reproduce the Talos bootstrap on the single-node Proxmox host (`atlas`) and the follow-on platform work (tailscale, kube-vip, GitOps apps).

## 🎉 CURRENT STATUS: FULLY FUNCTIONAL CLUSTER ACHIEVED

**What We Have**: A **fully operational 5-node Talos Kubernetes cluster** deployed via single `terraform apply` command with complete automation.

### What We Successfully Achieved:
- **✅ 5-node Talos cluster**: 3 controllers + 2 workers fully operational
- **✅ Terraform automation**: Single `tf apply` creates complete working cluster
- **✅ Image Factory integration**: QCOW2 disk images with baked-in static IP configuration
- **✅ Static IP networking**: No DHCP dependency, boot directly to predetermined IPs
- **✅ Talos v1.11.2** with Kubernetes v1.32.1
- **✅ VIP high availability**: 10.0.0.20 load-balances across all controllers  
- **✅ CNI networking**: Cilium v1.16.5 with Talos-specific security configuration
- **✅ Tailscale extensions**: Via Image Factory schematic (ready for activation)
- **✅ QEMU guest agent**: For Proxmox integration

### Quick Access Commands:

**Kubernetes cluster access:**
```bash
cd /home/agentydragon/code/cluster
# KUBECONFIG automatically set via .envrc
kubectl get nodes -o wide
```

**Using VIP for high availability:**
```bash
kubectl --server=https://10.0.0.20:6443 get nodes
```

**Talos management:**
```bash
cd /home/agentydragon/code/cluster
direnv exec . talosctl --nodes 10.0.0.11,10.0.0.12,10.0.0.13 version
```

### Current Architecture:
- **Controllers**: `10.0.0.11`, `10.0.0.12`, `10.0.0.13` (c0, c1, c2)
- **Workers**: `10.0.0.21`, `10.0.0.22` (w0, w1)
- **Cluster VIP**: `10.0.0.20` (✅ Active and load-balancing)
- **Network**: All nodes on 10.0.0.0/16 with gateway 10.0.0.1
- **CNI**: Cilium v1.16.5 providing networking and security

### Key Implementation Details:
- **Image Factory**: QCOW2 disk images with META key 10 static IP configuration
- **Terraform Modules**: Clean per-node architecture with unified configuration
- **Bootstrap Automation**: Single `terraform apply` handles everything
- **Extension Integration**: Tailscale + QEMU agent via Image Factory schematics
- **VIP Management**: Automatic kube-vip deployment for high availability

This cluster is **fully declarative and reproducible** via Terraform!

## Repository Structure
- `terraform/`: All Terraform configurations for Proxmox VMs and Talos cluster
- `BOOTSTRAP.md`: Step-by-step cluster deployment instructions
- `PLAN.md`: This document - project overview and architecture
- `.envrc`: Direnv configuration (auto-exports KUBECONFIG and TALOSCONFIG)

## Deployment Workflow

### Prerequisites
- Proxmox API credentials in Ansible vault
- Internet access for downloading providers and images
- `direnv` configured in cluster directory

### Single Command Deployment
```bash
cd /home/agentydragon/code/cluster/terraform
./tf.sh apply
```

This single command:
- Downloads QCOW2 disk images from Talos Image Factory
- Creates 5 VMs (105-109) with static IP configuration 
- Bootstraps the complete Kubernetes cluster
- Configures VIP high availability

### Teardown / Rebuild
```bash
./tf.sh destroy  # Remove all VMs and resources
./tf.sh apply    # Recreate from scratch
```

## Post-Deployment: Adding CNI

After Terraform completes, nodes will be `NotReady` until CNI is installed:

```bash
cd /home/agentydragon/code/cluster
# KUBECONFIG already set via .envrc

# Install Cilium CNI
helm repo add cilium https://helm.cilium.io/
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

# Verify all nodes become Ready
kubectl get nodes
```

## 5. GitOps / platform services roadmap
1. **Cluster management**
   - Install Flux (or Argo) once Phase 1 is stable. Store manifests/HelmReleases in this repo or a dedicated GitOps repo.
   - Use SOPS (age) or another sealed-secrets mechanism for Kubernetes secrets.
2. **Core add-ons**
   - kube-vip (tailscale VIP) + CNI (Talos default: Flannel)
   - Ingress controller (Traefik or NGINX) + cert-manager (ACME DNS-01 via Cloudflare)
   - Vault for secret storage; integrate with Authentik for SSO
   - Harbor (container registry) and Gitea
   - Synapse (Matrix), Atuin server, Guacamole (Linux desktop via SSO)
   - Observability stack: kube-prometheus-stack, Loki, Tempo, Velero backups
3. **Tunnels / DNS**
   - Public ingress served via `*.agentydragon.com` (reserve `k3s.*` separately).
   - Nodes register with headscale using the auth key pulled from the vault.
4. **Future TODOs**
   - Capture kube-vip deployment manifest/HelmRelease in Git.
   - Flesh out Flux directory structure + automation for Vault/Authentik wiring.

## 6. META Key Configuration for Static IP Baking (Working Solution)

### Current Implementation: Talos Image Factory with META Key 10

**✅ WORKING**: Successfully implemented static IP configuration baked directly into ISOs using Talos Image Factory META keys.

#### Key Source Code Locations:

**Talos META Implementation:**
- **META Constants**: `/mnt/tankshare/code/github.com/siderolabs/talos/pkg/machinery/meta/constants.go`
  - Key 10 (`MetalNetworkPlatformConfig`): Stores serialized NetworkPlatformConfig for metal platform
- **META Encoding**: `/mnt/tankshare/code/github.com/siderolabs/talos/pkg/machinery/meta/meta.go`  
  - Base64 + gzip encoding for META values
- **Platform Network Config**: `/mnt/tankshare/code/github.com/siderolabs/talos/internal/app/machined/pkg/runtime/v1alpha1/platform/nocloud/testdata/expected-v2.yaml`
  - Shows correct YAML structure for PlatformNetworkConfig

**Image Factory Integration:**
- **Profile Enhancement**: `/mnt/tankshare/code/image-factory/internal/profile/profile.go:474-483`
  - Lines 474-483: Converts schematic META values to profile customization
  - `prof.Customization.MetaContents` populated from `schematic.Customization.Meta`

#### Working META Key 10 Configuration:

```hcl
meta = [
  {
    key   = 10  # META key 0xa for network configuration  
    value = yamlencode({
      addresses = [
        {
          address   = "${var.ip_address}/16"
          linkName  = "eth0"
          family    = "inet4"
          scope     = "global"
          flags     = "permanent"
          layer     = "platform"
        }
      ]
      routes = [
        {
          family       = "inet4"
          dst          = ""
          gateway      = var.gateway
          outLinkName  = "eth0"
          table        = "main"
          priority     = 1024
          scope        = "global"
          type         = "unicast"
          protocol     = "static"
          layer        = "platform"
        }
      ]
      hostnames = [
        {
          hostname = var.node_name
          layer    = "platform"
        }
      ]
      resolvers = [
        {
          dnsServers = ["1.1.1.1", "8.8.8.8"]
          layer      = "platform"
        }
      ]
    })
  }
]
```

#### How it Works:

1. **Terraform Schematic Creation**: `local.schematic_yaml` includes META key 10 with network config
2. **Image Factory Processing**: POST to `/schematics` API processes META values  
3. **Profile Enhancement**: `EnhanceFromSchematic()` converts META to `prof.Customization.MetaContents`
4. **ISO Generation**: Custom ISO generated with baked-in network configuration
5. **Boot-time Application**: Talos reads META key 10 and applies static network config before any other networking

#### Benefits:
- **Zero DHCP Dependency**: VMs boot directly into predetermined static IPs
- **Deterministic Networking**: No need to chase DHCP leases or reservations  
- **Terraform-managed**: ISO regeneration automatically triggered on config changes
- **Platform Layer**: Network config applied at lowest level, before userspace

#### Test Results:
```bash
$ ping -c 3 10.0.0.11
64 bytes from 10.0.0.11: icmp_seq=1 ttl=64 time=0.151 ms
64 bytes from 10.0.0.11: icmp_seq=2 ttl=64 time=0.175 ms  
64 bytes from 10.0.0.11: icmp_seq=3 ttl=64 time=0.097 ms
```

**Working module location**: `/home/agentydragon/code/cluster/terraform/modules/talos-node/main.tf`

## 7. Bootstrap Process Documentation

### Our Talos Cluster Bootstrap Approach

**✅ WORKING**: Successfully implemented end-to-end Talos cluster deployment using Terraform + Image Factory with static IP configuration.

#### Architecture Overview
- **5-node cluster**: 3 controllers + 2 workers
- **Static IP allocation**:
  - Controllers: 10.0.0.11, 10.0.0.12, 10.0.0.13
  - Workers: 10.0.0.21, 10.0.0.22
  - Cluster VIP: 10.0.0.20 (shared across controllers)

#### Bootstrap Sequence

**Phase 1: VM Creation & Static IP Boot**
1. **Terraform creates VMs**: Each node gets unique ISO with baked-in META key 10 network config
2. **Static IP boot**: VMs boot directly to predetermined IPs (no DHCP dependency)
3. **Extensions loaded**: QEMU guest agent + Tailscale extensions active at boot

**Phase 2: Cluster Configuration**
1. **Machine configs applied**: Terraform applies Talos configurations to all 5 nodes
2. **Initial endpoint**: `cluster_endpoint = "https://10.0.0.11:6443"` (first controller)
3. **Certificate distribution**: All nodes receive cluster certificates and join tokens

**Phase 3: Bootstrap & VIP Establishment**  
1. **Manual bootstrap**: `talosctl bootstrap --endpoints 10.0.0.11 --nodes 10.0.0.11`
2. **etcd cluster formation**: First controller initializes etcd, others join
3. **Kubernetes API startup**: Controllers start serving API on their individual IPs
4. **VIP activation**: kube-vip establishes 10.0.0.20 floating between controllers

#### Critical Bootstrap Fix: The VIP Chicken-and-Egg Problem

**Problem Discovered:**
- Initial config had `cluster_endpoint = "https://10.0.0.20:6443"`  
- But VIP (10.0.0.20) doesn't exist until **after** bootstrap completes
- Nodes couldn't connect to non-existent VIP → bootstrap hung indefinitely

**Solution Applied:**
```hcl
# Phase 1: Bootstrap against first controller
cluster_endpoint = "https://10.0.0.11:6443"

# Phase 2: After bootstrap, VIP becomes available  
# Then clients can use either:
# - Individual controller IPs: 10.0.0.11:6443, 10.0.0.12:6443, 10.0.0.13:6443
# - Shared VIP: 10.0.0.20:6443 (automatically load balanced)
```

#### VIP High Availability Mechanism
- **Each controller runs kube-vip** for leader election
- **Current leader owns** the VIP (10.0.0.20)
- **Leader distributes traffic** to all healthy controllers
- **Automatic failover** if leader becomes unhealthy

#### Key Implementation Details
- **META key 10 network config**: Baked into ISOs for boot-time static IP
- **Terraform module structure**: Clean separation per node with restart notifications
- **Extension integration**: Tailscale + QEMU agent via Image Factory schematics
- **Bootstrap sequence**: Direct controller IP → VIP establishment → HA cluster

## External Connectivity & Ingress Architecture

### Complete HTTPS Connectivity Stack

**Operational**: External services accessible via `*.test-cluster.agentydragon.com` with automatic HTTPS and SSL termination.

#### Architecture Flow
```
Internet → VPS (nginx proxy + Let's Encrypt SSL) 
        → Tailscale VPN 
        → Talos worker nodes (NodePort 30443)
        → NGINX Ingress Controller 
        → Application pods
```

#### Key Components

**1. VPS Proxy Configuration**
- **DNS**: `*.test-cluster.agentydragon.com` → VPS IP
- **SSL**: Let's Encrypt wildcard certificate via PowerDNS DNS-01 validation  
- **Proxy**: nginx forwards to `w0:30443` via Tailscale hostname resolution

**2. Cluster NodePort Configuration**
- **NGINX Ingress**: 2 replicas on worker nodes w0/w1 with pod anti-affinity
- **NodePort Service**: `30080/TCP,443:30443/TCP` accessible on all worker nodes
- **Cilium Configuration**: `kubeProxyReplacement: true` with `bindProtection: false`

**3. Application Deployment**
- **GitOps**: Applications deployed via Flux from `/apps` directory
- **Ingress**: Standard Kubernetes ingress resources with nginx class
- **DNS**: Automatic routing based on Host headers

#### Configuration Files
- **VPS**: `/home/agentydragon/code/ducktape/ansible/nginx-sites/test-cluster.agentydragon.com.j2`
- **NGINX Ingress**: `/home/agentydragon/code/cluster/apps/ingress-system/helmrelease.yaml`
- **Cilium**: `/home/agentydragon/code/cluster/apps/cilium/helmrelease.yaml`
- **Test App**: `/home/agentydragon/code/cluster/apps/test-app/`

#### Debugging Journey: DaemonSet → Deployment Conversion

**Initial Problem**: NGINX ingress was configured as DaemonSet on control-plane nodes with hostNetwork, causing:
- Port conflicts when multiple controllers try to bind to same ports
- Certificate issues between duplicate HelmReleases
- Node readiness issues (kubelet services failing)

**Solution Applied**:
1. **Architecture Change**: DaemonSet → Deployment for better resource management
2. **Node Targeting**: Control-plane → Worker nodes (both have Tailscale connectivity) 
3. **Networking**: hostNetwork → NodePort for proper service exposure
4. **High Availability**: 2 replicas with pod anti-affinity across worker nodes
5. **Configuration Cleanup**: Removed duplicate ingress-nginx namespace/configuration

**Final Working Configuration**:
```yaml
controller:
  kind: Deployment
  replicaCount: 2
  service:
    type: NodePort 
    nodePorts:
      http: 30080
      https: 30443
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: node-role.kubernetes.io/control-plane
            operator: DoesNotExist
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchLabels:
              app.kubernetes.io/name: ingress-nginx
              app.kubernetes.io/component: controller
          topologyKey: kubernetes.io/hostname
```

## GitOps Workflow

### Repository Setup
- **Source Code**: https://github.com/agentydragon/cluster
- **Structure**:
  ```
  cluster/
  ├── terraform/           # Infrastructure as Code
  ├── flux-system/         # Flux controllers (auto-generated)
  ├── apps/               # Application manifests
  │   ├── cilium/         # CNI configuration
  │   ├── monitoring/     # Prometheus, Grafana
  │   └── ingress/        # NGINX ingress
  ├── BOOTSTRAP.md        # Deployment instructions
  └── PLAN.md            # This document
  ```

### Bootstrap Flux
```bash
cd /home/agentydragon/code/cluster
flux bootstrap github \
  --owner=agentydragon \
  --repository=cluster \
  --path=flux-system \
  --personal \
  --read-write-key
```

### GitOps Workflow
1. **Make changes**: Edit YAML files locally or via GitHub
2. **Commit & Push**: Standard Git workflow  
3. **Auto-deploy**: Flux detects changes and applies to cluster
4. **Observe**: Monitor via `flux get all` or Kubernetes dashboard

## Checklist / Status
- [x] **Image Factory Integration**: VMs created with QCOW2 disk images containing baked-in static IP configuration
- [x] **Static IP Boot**: All 5 VMs boot with predetermined static IPs without DHCP dependency
- [x] **Scale to full 5-node cluster**: 3 controllers + 2 workers deployed
- [x] **Talos machine configurations applied**: All nodes configured via Terraform
- [x] **Bootstrap endpoint fix**: Changed from VIP to first controller to resolve chicken-and-egg
- [x] **Automated bootstrap execution**: Complete cluster initialization via terraform
- [x] **CNI Installation**: Cilium v1.16.5 CNI installed with Talos-specific configuration
- [x] **VIP establishment**: 10.0.0.20 active and load-balancing across all controllers
- [x] **Kubernetes cluster ready**: All 5 nodes show Ready status
- [x] **Tailscale connectivity**: All nodes connected to headscale mesh (100.64.0.14-18)
- [x] **Repository setup**: Cluster configuration published to GitHub
- [x] **GitOps setup**: Flux fully operational for declarative cluster management
- [x] **External HTTPS connectivity**: Complete VPS proxy → Tailscale → cluster ingress chain
- [x] **NGINX Ingress HA**: 2 replicas on worker nodes with NodePort 30080/30443
- [x] **Platform services**: Cilium CNI, cert-manager, ingress-nginx deployed via GitOps
- [x] **End-to-end testing**: Test application accessible via https://test.test-cluster.agentydragon.com/
- [ ] **Backup/recovery**: Document cluster restore procedures
