# Claude Code Instructions

## SSH Access

Use `ssh root@atlas` to access the Proxmox host. No password required (SSH keys configured).

## Talos CLI Access

- Run `talosctl` commands from cluster directory (direnv auto-loaded)
- Use `direnv exec /home/agentydragon/code/cluster talosctl` if running from other directories
- The direnv config automatically sets `TALOSCONFIG` path and provides talosctl via nix

## Working Directory

- Infrastructure terraform config: `/home/agentydragon/code/cluster/terraform/infrastructure/`
- GitOps terraform config: `/home/agentydragon/code/cluster/terraform/gitops/`
- VM IDs: 1500-1502 (controlplane0-2), 2000-2001 (worker0-1)
- Node IPs: 10.0.1.x (controllers), 10.0.2.x (workers), 10.0.3.x (VIPs)

## Reference Code Location

- `/mnt/tankshare/code/` - Directory for cloned source code and reference implementations
- `/mnt/tankshare/code/github.com/rgl/` - The RGL terraform-proxmox-talos configuration this project was built upon
  - Uses `./do init` to build custom Talos qcow2 images with extensions via Docker imager
  - The `build_talos_image()` function creates `tmp/talos/talos-${version}.qcow2` locally

## Key Files

- `talos.tf` - Talos machine configurations with Tailscale
- `proxmox.tf` - VM definitions
- `variables.tf` - Configuration variables
- `vault-secrets.tf` - Ansible vault integration via external data source

## Project Documentation Strategy

### docs/BOOTSTRAP.md

**Purpose**: ONLY straight-line sequence to recreate a functioning cluster from unpopulated Proxmox.

**Content**:

- Step-by-step instructions for cold-starting the Talos cluster from nothing
- Complete deployment procedures (terraform, CNI, applications, external connectivity)
- Basic verification steps only (run `terraform/infrastructure/health-check.sh`)
- **NO troubleshooting** (would be too verbose - half a megabyte)

**Maintenance**: Continuously update to reflect current state. Changes require BOOTSTRAP.md updates.

### docs/OPERATIONS.md

**Purpose**: Day-to-day cluster management procedures including scaling, maintenance, and troubleshooting.

**Content**:

- Node operations (adding, removing, restarting)
- System diagnostics and VM console management
- Comprehensive troubleshooting guide with symptoms and solutions
- Reference information (IP assignments, file locations)

**Maintenance**: Updated when operational procedures change or new troubleshooting scenarios are discovered.

### docs/PLAN.md

**Purpose**: Describes high-level goals we want to implement, lists what we finished, and what remains to be done as items.

**Content**:

- Project overview and architecture decisions
- Completed features with status markers ([x])
- Remaining tasks as checkbox items ([ ])
- Partially complete tasks as ([ ] PARTIAL)
- Design documents for planned features
- Strategic technical decisions and rationale

**Maintenance**: Tracks project roadmap. Move completed items to "Achieved" sections, add new goals.

## Key Principles

1. **docs/BOOTSTRAP.md is always actionable** - anyone should be able to follow it and get a working cluster
2. **docs/PLAN.md is strategic** - focuses on what we're building and why
3. **Keep both in sync** - when implementation is complete, move details from docs/PLAN.md to docs/BOOTSTRAP.md
4. **Document current state accurately** - especially important for infrastructure that changes over time

## Command Execution Context

**All kubectl, talosctl, kubeseal, flux, and helm commands** assume cluster directory execution or `direnv exec .`.

This provides consistent tool versions (nix-managed) and automatic KUBECONFIG/TALOSCONFIG environment variables.

## Checklist

- **Before making changes**: Read docs/BOOTSTRAP.md to understand current working state
- **After completing work**: Update docs/BOOTSTRAP.md with new procedures if they change the bootstrap sequence
- **When planning**: Use docs/PLAN.md to understand goals and add new tasks
- **When finishing features**: Mark items complete in docs/PLAN.md and ensure docs/BOOTSTRAP.md reflects the new capabilities

This ensures the documentation serves both as operational procedures (docs/BOOTSTRAP.md) and project management (docs/PLAN.md).
