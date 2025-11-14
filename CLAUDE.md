# Claude Code Instructions

## PRIMARY DIRECTIVE: DECLARATIVE TURNKEY BOOTSTRAP

**The primary goal is to achieve a committed repo state where `terraform apply` → everything works.**

### Objective

Achieve a committed repository state such that:

1. `terraform apply` (or equivalent O(1) minimal steps documented in BOOTSTRAP.md)
2. **Everything works**

Where "everything" means everything currently in PLAN.md scope as specified by user.

### Scope Evolution Strategy

**Spiral development approach:**

- **v0**: Turnkey basic cluster
- **v1**: Add service X, iterate until reliable and turnkey, commit when working
- **v2**: Add service Y, iterate until reliable and turnkey, commit when working
- **v∞**: Eventually migrate services from other infrastructure

**Core Services (minimum viable scope):**

- Authentik SSO
- Gitea with SSO
- Harbor with SSO
- Matrix with SSO

**Future Services:**

- CI in Gitea
- Services from ducktape VPS (Inventree, Grocy, PowerDNS, agentydragon.com)
- Ember agent + turnkey evals + RBAC
- Host GPU LLMs

**Principle**: Whatever subset of PLAN.md is "currently in scope" must be turnkey deployable before expanding scope.

### Definition of "Done"

**You are NOT done unless:**

1. You have turnkey `terraform apply` (+ O(1) documented BOOTSTRAP.md steps)
2. That **reliably** results in everything in-scope functioning
3. **Without needing ANY further manual tweaks**

**Completion criteria:**

- `terraform destroy` → `terraform apply` → run all health checks
- **If ANY component is unhealthy, it does NOT work by definition**
- No declaring "good enough" or aborting work on broken turnkey flow

**Only hand over as "it works" after full destroy→apply→verify cycle passes.**

### Core Principles

1. **NO imperative patches** - All fixes must be encoded in configuration and committed properly
2. **Main development loop**: `destroy -> recreate -> check if valid`
3. **Debugging vs. Implementation**:
   - **Debugging**: You CAN tinker with invalid/failed state (kubectl patches, manual commands) to understand what
     broke and learn how to fix declarative config
   - **Implementation**: All solutions MUST be declarative configuration changes, never manual fixes
   - **"The cluster works" ≠ DONE** - Getting broken state functioning via manual patches is NOT completion
4. **End-to-end declarative working config** - The outer true goal is always complete declarative automation

### Development Workflow

```bash
# Primary loop for all changes:
terraform destroy --auto-approve
terraform apply --auto-approve
# Verify: does it work end-to-end declaratively?
```

## Primary Development Loop

Main cycle: **destroy → recreate → check if valid**

If the result is broken/invalid, you may inspect and debug the live state to understand the failure. But the fix MUST be
committed configuration changes that make the next destroy→recreate cycle work properly.

### Cluster Disposability

**The cluster is completely disposable.** If it gets corrupted/broken, just `terraform destroy` it. Don't bother repairing
running state.

### Debugging vs. Completion Distinction

**Debugging a broken cluster:**

- You CAN tinker, patch, run manual kubectl commands
- Purpose: Learn WHY the declarative config failed
- Goal: Understand what needs to be fixed in committed configuration

**Completion criteria:**

- **"The cluster works" ≠ DONE**
- Getting current broken instance functioning via patches is NOT completion
- **DONE = teardown & apply results in working cluster**
- Must pass: `terraform destroy && terraform apply` → all components healthy

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

**Base**: `/mnt/tankshare/code` using `domain.tld/org/repo` pattern

**Key references:**

- `github.com/rgl/terraform-proxmox-talos` - Reference config, `./do init` builds custom images
- `github.com/longhorn/longhorn-charts` - Longhorn schemas at `charts/longhorn/values.yaml`
- `github.com/bank-vaults/bank-vaults` - Bank-Vaults operator source
- `github.com/fluxcd/flux2` - Flux CD examples
- `github.com/bpg/terraform-provider-proxmox` - Proxmox provider
- `github.com/siderolabs/terraform-provider-talos` - Talos provider

Use cloned repos as implementation ground truth.

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

1. **DECLARATIVE FIRST** - All configuration must work via destroy->recreate cycle without manual intervention
2. **docs/BOOTSTRAP.md is always actionable** - anyone should be able to follow it and get a working cluster
3. **docs/PLAN.md is strategic** - focuses on what we're building and why
4. **Keep both in sync** - when implementation is complete, move details from docs/PLAN.md to docs/BOOTSTRAP.md
5. **Document current state accurately** - especially important for infrastructure that changes over time
6. **Debug broken state to understand, but fix via committed config** - Never leave manual patches as the solution

## Command Execution Context

**All kubectl, talosctl, kubeseal, flux, and helm commands** assume cluster directory execution or `direnv exec .`.

This provides consistent tool versions (nix-managed) and automatic KUBECONFIG/TALOSCONFIG environment variables.

## Terraform Timeout Configuration

**IMPORTANT**: When running `terraform apply` or `terraform destroy`, always use the Bash tool's `timeout` parameter
set to 600000ms (10 minutes) to prevent premature timeout during long cluster provisioning operations.

Example:

```json
{
  "command": "terraform apply -auto-approve",
  "timeout": 600000,
  "description": "Apply terraform with maximum timeout"
}
```

Never use the `timeout` command prefix - use the tool's built-in timeout parameter instead.

## Checklist

- **Before making changes**: Read docs/BOOTSTRAP.md to understand current working state
- **After completing work**: Update docs/BOOTSTRAP.md with new procedures if they change the bootstrap sequence
- **When planning**: Use docs/PLAN.md to understand goals and add new tasks
- **When finishing features**: Mark items complete in docs/PLAN.md and ensure docs/BOOTSTRAP.md reflects the new capabilities

This ensures the documentation serves both as operational procedures (docs/BOOTSTRAP.md) and project management (docs/PLAN.md).
