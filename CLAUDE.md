# Claude Code Instructions

## SSH Access
- Use `ssh root@atlas` to access the Proxmox host
- No password required (SSH keys configured)

## Talos CLI Access
- Use `direnv exec /home/agentydragon/code/cluster talosctl` to run talosctl commands
- The direnv config automatically sets TALOSCONFIG path and provides talosctl via nix

## Working Directory
- Main terraform config: `/home/agentydragon/code/cluster/infrastructure/terraform/proxmox/`
- Working 5-node Talos cluster with Tailscale extensions already deployed
- VMs 105-111 are the working cluster nodes

## Reference Code Location
- `/mnt/tankshare/code/` - Directory for cloned source code and reference implementations
- `/mnt/tankshare/code/github.com/rgl/` - The RGL terraform-proxmox-talos configuration this project was built upon
  - Uses `./do init` to build custom Talos qcow2 images with extensions via Docker imager
  - The `build_talos_image()` function creates `tmp/talos/talos-${version}.qcow2` locally

## Key Files
- `talos.tf` - Talos machine configurations with Tailscale
- `proxmox.tf` - VM definitions
- `variables.tf` - Configuration variables
- `tf.sh` - Terraform wrapper script with environment variables