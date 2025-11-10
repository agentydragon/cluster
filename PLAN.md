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

### Architecture Evolution (Historical)

#### Option 1: Kernel cmdline with `talos.config.inline` ❌ BLOCKED BY PROVIDER LIMITATION
- [x] **PROVIDER GAP**: BPG Terraform provider lacks dedicated `kernel_cmdline` or `boot_args` field
- [x] **WORKAROUND BLOCKED**: Only available method is `kvm_arguments` field, which requires root API token
- [x] **SECURITY RESTRICTION**: `kvm_arguments` passes arbitrary QEMU args (security risk) - restricted to root
- [x] **VERDICT**: Kernel parameters artificially blocked by missing provider feature, not Proxmox itself

#### Option 2: Multiple CDROM approach with official images ❌ **BLOCKED BY PROVIDER**
- [x] **CONFIRMED**: BPG provider supports multiple CDROM drives via multiple `cdrom` blocks
- [x] **INTERFACES**: `ideN`, `sataN`, `scsiN` (Q35 machines limited to `ide0`, `ide2`)
- [x] **CAPABILITY**: Can attach multiple ISOs with different interface indexes
- [x] **CRITICAL LIMITATION DISCOVERED**: Provider only allows **one `cdrom` block per VM**
- [x] **ERROR**: `"Too many cdrom blocks" - "No more than 1 "cdrom" blocks are allowed"`
- [x] **SOURCE CODE**: [proxmoxtf/resource/vm/vm.go:538](https://github.com/bpg/terraform-provider-proxmox/blob/main/proxmoxtf/resource/vm/vm.go#L538) - `MaxItems: 1` constraint
- [x] **IMPACT**: Cannot simultaneously attach boot ISO + config ISO via Terraform
- [x] **WORKAROUND**: Requires manual CDROM switching or post-Terraform CLI manipulation

#### Option 3: HTTP server patterns
- [ ] Research Proxmox built-in HTTP server capabilities for config delivery
- [ ] Investigate standard sidecar patterns for Proxmox configuration
- [ ] Test if HTTP server needs to persist post-boot or just for initial provisioning
- [ ] Evaluate "turn on once, forget about it" solutions

#### Option 4: Fix corrupted image download (fallback) ⭐ **RECOMMENDED**
- [ ] **PRIORITY**: Diagnose why `null_resource.talos_image_download` produces 9-byte file
- [ ] Fix download process to get proper Talos qcow2 file  
- [ ] Test terraform apply with working image file
- [ ] **RATIONALE**: Returns to known-working RGL approach fastest

### Final Architecture:
- **Controllers**: `10.0.0.11`, `10.0.0.12`, `10.0.0.13` 
- **Workers**: `10.0.0.21`, `10.0.0.22`
- **Cluster VIP**: `10.0.0.20` (configured but not yet active - needs CNI)
- **Network**: All nodes on home 10.0.0.0/16 with gateway 10.0.0.1

### How to Access the Cluster:

**Quick kubectl access:**
```bash
export KUBECONFIG=/home/agentydragon/code/cluster/terraform/kubeconfig.yml
kubectl get nodes -o wide
```

**Talos management:**
```bash  
talosctl -e 10.0.0.11 -n 10.0.0.11 version
```

### Implementation Notes:
- **RGL Approach**: Used [rgl/terraform-proxmox-talos](https://github.com/rgl/terraform-proxmox-talos) patterns
- **Custom Talos Images**: Built with extensions instead of vanilla Talos + nocloud  
- **Network Fix**: Corrected from 10.5.0.x to 10.0.0.x to match home network
- **Storage Fix**: Added `images` content type support to Proxmox `local` storage
- **SSH Auth Fix**: Used private key instead of ssh-agent for Terraform provider

This cluster is **fully declarative and reproducible** via Terraform!

## 0. Repo layout quick reference
- `infrastructure/terraform/proxmox/`: Terraform that provisions the Talos VMs and downloads the ISO via the `bpg/proxmox` provider. Wrapper script: `tf.sh`.
- `talos/home/`: Talos machine config templates (`templates/`), `nodes.json` as the single source of truth for DHCP/static addresses, render/apply scripts, generated output (`generated/phase1`, `generated/phase2`), and the local `talosctl` binary.
- `.envrc` + `pyproject.toml`: direnv-managed virtualenv that installs PyYAML and any future Python deps so the render/apply scripts just work.

## 1. Terraform on Proxmox
1. **Secrets + prerequisites**
   - `tf.sh` reads the Ansible vault in `~/code/ducktape/ansible/terraform-secrets.vault` using `secret-tool lookup service=ansible-vault account=ducktape`.
   - Vault entries must contain `vault_proxmox_terraform_token_id` (`user@realm!token`) and `vault_proxmox_terraform_token_secret`.
   - Run Terraform from a host with outbound internet access: the sandbox must download the `bpg/proxmox` provider from `registry.terraform.io` *and* the Talos ISO from GitHub (`talos_iso_url`, currently v1.11.5).

2. **Workflow**
   - `cd infrastructure/terraform/proxmox`
   - `./tf.sh init` → installs providers, configures local backend.
   - `./tf.sh plan` / `apply` → downloads the ISO onto `local:iso/` (overwriting existing file), then creates the 5 Talos VMs (vmids 300-304) with deterministic MACs, `q35` + `ovmf`, virtio NICs, and `on_boot = true`.
   - VM network: Proxmox `ipconfig0` strings request `10.0.230.x`, but *Talos ignores cloud-init*, so guests still take DHCP leases (`10.0.232.*`). Deterministic MACs mean home router reservations could enforce the intended addresses later if desired.
   - Terraform does **not** manage templates anymore; it always downloads the upstream ISO so we can stay on stock Talos releases.

3. **Teardown / rebuild**
   - `./tf.sh destroy` removes all Talos VMs but leaves the downloaded ISO in Proxmox storage.
   - After a destroy, re-run `./tf.sh apply` to bring back clean VMs with the same MAC/vmid assignments.

## 2. Talos config rendering
1. `talos/home/nodes.json` schema (single source of truth for DHCP leases):
   ```json
   {
     "control_plane_vip": "tailscale-vip-placeholder",
     "headscale_login_server": "https://agentydragon.com:8080",
     "controlplanes": [{"name":"talos-cp-01","dhcp":"10.0.232.93"}],
     "workers": [{"name":"talos-worker-01","dhcp":"10.0.232.109"}]
   }
   ```
   - `dhcp` is the lease currently assigned by the home router. Deterministic MACs mean leases are stable unless the router resets; update this file whenever they change.
   - `address` fields are no longer required (we’re committing to DHCP + tailscale). Only add them back if you later want a Phase‑2 static conversion or router reservations.
   - Apply scripts read only from this file, so keeping it accurate guarantees render/apply stays in sync.

2. `render.py`
   - Run from `talos/home/` after `direnv allow` so PyYAML is available.
   - Loads the Headscale/Tailscale auth key **exclusively** from `~/code/ducktape/ansible/terraform-secrets.vault` (key `vault_headscale_api_key`). If missing, it prints the vault contents and raises an error—no silent fallbacks.
   - Output layout:
     ```
     generated/
       phase1/
         controlplanes/*.yaml      # DHCP configs (dhcp: true) + embedded tailscale ExtensionServiceConfig doc
         workers/*.yaml
       phase2/ (optional)
         ...                       # static LAN configs (only used if we later decide to pin LAN IPs)
     ```
   - Phase 1 machine configs keep `dhcp: true` and point `CONTROL_PLANE_VIP` at the bootstrap node. Phase 2 disables DHCP, sets the static addresses, and expects kube-vip to own the VIP.

## 3. Bootstrap timeline
1. **Before Talos**
   - Use Terraform (above) to create / recreate the VMs. Note their DHCP leases via router UI or `qm monitor`.
   - Update `nodes.json` with the current `dhcp` values (or run `talos/home/update_nodes.py` if the helper defaults still match reality).

2. **Phase 1 (DHCP)**
   1. `cd talos/home`
   2. `./render.py`
   3. `./apply_phase1.py` → loops control planes + workers, re-renders automatically, runs `talosctl apply-config` against each DHCP IP, waits for `apid` to come back (handles insecure ↔ secure transitions), and moves on. The tailscale `ExtensionServiceConfig` rides inside the same YAML file, so there’s no separate apply step.
   4. As soon as the first control-plane reports `STATE Running`, run `../talosctl-linux-amd64 bootstrap --nodes <control-plane DHCP IP> --endpoints <same IP> --talosconfig talos/home/talosconfig` (e.g., `10.0.232.93`). This initializes etcd/Kubernetes and lets the rest of the nodes join cleanly.

3. **Install kube-vip on tailscale**
   - Deploy kube-vip (Helm or raw manifest) in `kube-system`, configured with `vip_interface: tailscale0` and advertising a VIP inside the Tailscale network (e.g., `100.x.y.z`). This VIP becomes the stable Talos/Kubernetes endpoint regardless of LAN IP churn.
   - Record that VIP in `nodes.json.control_plane_vip`. Phase 1 already uses this field for `talosctl` endpoints; we no longer need Phase 2 unless we choose to introduce static LAN addresses later.

4. **Phase 2 (optional static LAN)**
   - Skipped by default. If we later want fixed LAN IPs, reintroduce the `address` fields, re-render, and run `apply_phase2.py` to flip Talos networking. Until then, all management and Kubernetes access runs over DHCP + tailscale.

5. **Ongoing updates**
   - Any time you tweak `nodes.json`, re-run `render.py` and whichever apply script matches your phase. The scripts look up `generated/phase{1,2}` so they always stay in sync.

## 4. Networking + Tailscale notes
- Deterministic MACs mean you can add DHCP reservations on the home router later if you need predictable LAN IPs (without re-running Phase 2).
- Talos ignores Proxmox `ipconfig0`, so the only supported way to change networking is through Talos machine configs (or DHCP reservations outside the cluster).
- The tailscale extension uses the Headscale auth key; if you need to override (testing / new keys), set `HEADSCALE_AUTH_KEY=<value>` before running `render.py` or rely on the key pulled from the vault.
- `talos/home/templates/tailscale-extension.yaml.tpl` describes the tailscale service; `render.py` appends that doc to every machine config so tailscale is deployed automatically with each `apply-config`.

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

## 8. Checklist / status
- [x] **Image Factory Integration**: VMs created with QCOW2 disk images containing baked-in static IP configuration
- [x] **Static IP Boot**: All 5 VMs boot with predetermined static IPs without DHCP dependency
- [x] **Scale to full 5-node cluster**: 3 controllers + 2 workers deployed
- [x] **Talos machine configurations applied**: All nodes configured via Terraform
- [x] **Bootstrap endpoint fix**: Changed from VIP to first controller to resolve chicken-and-egg
- [x] **Automated bootstrap execution**: Complete cluster initialization via terraform
- [x] **CNI Installation**: Cilium v1.16.5 CNI installed with Talos-specific configuration
- [x] **VIP establishment**: 10.0.0.20 active and load-balancing across all controllers
- [x] **Kubernetes cluster ready**: All 5 nodes show Ready status
- [ ] **Tailscale connectivity**: Verify all nodes join headscale network (extension available)
- [ ] **GitOps setup**: Consider migrating from Helm to Flux/Argo for declarative cluster management
- [ ] **Platform services**: Deploy Vault, Authentik, Harbor, Gitea, etc. via GitOps
- [ ] **Backup/recovery**: Document cluster restore procedures
