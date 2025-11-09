# Home Proxmox → Talos Cluster Plan

This document tracks how to reproduce the Talos bootstrap on the single-node Proxmox host (`atlas`) and the follow-on platform work (tailscale, kube-vip, GitOps apps).

## 🎉 COMPLETION STATUS: SUCCESS!

**We have achieved the primary goal**: A fully functional **5-node Talos Kubernetes cluster** running on Proxmox with Tailscale extensions!

### What We Built:
- **✅ 5 Talos VMs** (3 controllers + 2 workers) with static IP networking
- **✅ Kubernetes v1.32.1** cluster fully bootstrapped and responsive  
- **✅ Talos v1.11.2** with custom-built images including extensions
- **✅ Tailscale v1.88.1** extension loaded on all nodes
- **✅ QEMU Guest Agent** for Proxmox integration
- **✅ Proper cloud-init networking** with 10.0.0.x static IPs

### Final Architecture:
- **Controllers**: `10.0.0.11`, `10.0.0.12`, `10.0.0.13` 
- **Workers**: `10.0.0.21`, `10.0.0.22`
- **Cluster VIP**: `10.0.0.20` (configured but not yet active - needs CNI)
- **Network**: All nodes on home 10.0.0.0/16 with gateway 10.0.0.1

### How to Access the Cluster:

**Quick kubectl access:**
```bash
export KUBECONFIG=/home/agentydragon/code/cluster/infrastructure/terraform/proxmox/kubeconfig.yml
kubectl get nodes -o wide
```

**Talos management:**
```bash  
export TALOSCONFIG=/home/agentydragon/code/cluster/infrastructure/terraform/proxmox/talosconfig.yml
/home/agentydragon/code/cluster/talos/talosctl-linux-amd64 -e 10.0.0.11 -n 10.0.0.11 version
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

## 6. Checklist / status
- [ ] Terraform apply run from workstation with internet → creates Talos VMs backed by Talos ISO 1.11.5.
- [ ] `nodes.json` updated with current DHCP leases.
- [ ] `apply_phase1.py` executed (it re-renders internally); control plane bootstrapped via `talosctl bootstrap`.
- [ ] kube-vip deployed on `tailscale0`, VIP recorded in `nodes.json`.
- [ ] (Optional) `apply_phase2.py` executed if we ever decide to migrate to static LAN IPs.
- [ ] Flux + platform services installed (Vault, Authentik, Harbor, Gitea, Synapse, Atuin, Guacamole, ingress, cert-manager, observability).
- [ ] Backup/recovery documented (Talos machine configs, kube-vip failover, Vault unseal keys, Authentik backups).
