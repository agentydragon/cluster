# Claude Code Instructions

## ⚠️ CRITICAL: REPOSITORY SCOPE

**Your work is confined to this cluster repository (`/home/agentydragon/code/cluster`) ONLY.**

**FORBIDDEN OPERATIONS:**

- Editing or pushing files outside this repository (e.g., ~/code/ducktape, other repos)
- Making commits in other repositories without explicit instruction
- Pushing changes to other git repositories (user controls those separately)

**PERMITTED OPERATIONS:**

- Reading reference code from `/code/*` for documentation and implementation patterns
- Suggesting changes for other repositories (user will implement them)
- Working with files exclusively in `/home/agentydragon/code/cluster`

**EXCEPTION:** Only edit/commit/push to other repositories when user explicitly instructs you to do so.

## PRIMARY DIRECTIVE: DECLARATIVE TURNKEY BOOTSTRAP

**The primary goal is to achieve a committed repo state where the bootstrap script → everything works.**

## ⚠️ CRITICAL: PERSISTENT AUTH PROTECTION

**AI agents and automated processes MUST NEVER destroy the persistent auth layer (00-persistent-auth) without
explicit user authorization.**

**FORBIDDEN OPERATIONS:**

- `cd terraform/00-persistent-auth && terraform destroy`
- Any command that would destroy CSI tokens or sealed secrets keypair
- "Clean slate" operations that include persistent auth

**PERMITTED OPERATIONS:**

- VM lifecycle: `cd terraform/01-infrastructure && terraform destroy && terraform apply`
- Services reset: Layers 02-services, 03-configuration
- Selective bootstrap: `./bootstrap.sh --start-from=infrastructure`

**RATIONALE:** The persistent auth layer contains:

- Proxmox CSI tokens (required for storage)
- Sealed secrets keypair (required for secret decryption)
- These survive VM teardown by design to prevent git commit churn and maintain storage continuity

## ⚠️ CRITICAL: COMMIT BEFORE RECONCILE

**NEVER attempt to reconcile Flux resources (HelmRelease, Kustomization, etc.) until changes are committed AND
pushed to origin.**

**MANDATORY WORKFLOW:**

1. Make changes to chart/manifest files
2. `git add -A && git commit -m "..." && git push`
3. ONLY THEN: `flux reconcile source git ...` followed by `flux reconcile helmrelease ...`

**WHY THIS MATTERS:**

- Flux fetches configuration from the git repository, not your local filesystem
- Reconciling before push = Flux uses OLD configuration = changes don't apply
- This wastes time trying to debug "why isn't my change working" when it simply hasn't been pushed yet

**SYMPTOMS OF FORGETTING TO PUSH:**

- Pods still show old errors after "fixing" them
- Environment variables not updated in deployment
- Template changes not reflected in rendered manifests
- Repeated reconciliation attempts with no effect

**CORRECT SEQUENCE:**

```bash
# 1. Edit files
vim charts/powerdns/templates/deployment.yaml

# 2. Commit and push FIRST
git add -A
git commit -m "fix: add missing environment variable"
git push

# 3. ONLY NOW reconcile Flux
flux reconcile source git powerdns-chart -n dns-system
flux reconcile helmrelease powerdns -n dns-system
```

**NEVER DO THIS:**

```bash
# ❌ WRONG: Reconciling before push
vim charts/powerdns/templates/deployment.yaml
flux reconcile helmrelease powerdns -n dns-system  # This uses OLD code!
git add -A && git commit && git push  # Too late, already tried to deploy
```

### Objective

Achieve a committed repository state such that:

1. `./terraform/infrastructure/bootstrap.sh` (the ONLY supported bootstrap method)
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

1. You have turnkey `./terraform/infrastructure/bootstrap.sh` (the ONLY supported method)
2. That **reliably** results in everything in-scope functioning
3. **Without needing ANY further manual tweaks**

**Completion criteria:**

- `terraform destroy` → `./terraform/infrastructure/bootstrap.sh` → run all health checks
- **If ANY component is unhealthy, it does NOT work by definition**
- No declaring "good enough" or aborting work on broken turnkey flow

**Only hand over as "it works" after full destroy→bootstrap→verify cycle passes.**

### Core Principles

1. **NO imperative patches** - All fixes must be encoded in configuration and committed properly
2. **Main development loop**: `destroy -> recreate -> check if valid`
   - See `docs/CRITICAL_DEPENDENCIES.md` for dependency chain and bootstrap order
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
./terraform/infrastructure/bootstrap.sh
# Verify: does it work end-to-end declaratively?
```

## Bootstrap Script - ONLY Supported Method

**CRITICAL**: The cluster MUST only be bootstrapped using `./terraform/infrastructure/bootstrap.sh`

### Why Bootstrap Script (Not Direct Terraform)

**Never run `terraform apply` directly.** The bootstrap script is required because:

1. **Preflight Validation**: Comprehensive checks before any infrastructure changes
   - Git working tree must be clean (Flux requirement)
   - Pre-commit validation (security, linting, format)
   - Terraform configuration validation
2. **Proper Error Handling**: Clear error messages and early failure detection
3. **Battle-tested Flow**: Proven sequence that prevents partial failure states
4. **Documentation**: Self-documenting deployment process

### Bootstrap Script Features

- **🔍 Preflight validation**: Git clean + pre-commit + terraform validate
- **⚡ Native provider deployment**: Talos → Cilium → Flux → Applications
- **🛡️ Libsecret keypair persistence**: Sealed secrets work across destroy/apply
- **📊 Clear progress reporting**: Phase-by-phase status updates
- **❌ Fail-fast behavior**: Stops immediately on any validation failure

### Usage

```bash
cd terraform/infrastructure
./bootstrap.sh
```

**That's it.** The script handles everything from validation to complete cluster deployment.

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
- **DONE = teardown & bootstrap results in working cluster**
- Must pass: `terraform destroy && ./bootstrap.sh` → all components healthy

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

**Base**: `/code` using `domain.tld/org/repo` pattern

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

### docs/TROUBLESHOOTING.md

**Purpose**: Fast-path diagnostic checklist for common cluster issues.

**Content**:

- Quick health checks for core components
- **Storage troubleshooting** (Proxmox CSI is known tricky - SealedSecret decryption issues)
- GitOps debugging commands
- Stable SealedSecret keypair verification
- Common recovery actions and known issues

**Maintenance**: Updated as new issues are discovered and resolved.

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
- **When diagnosing issues**: Use docs/TROUBLESHOOTING.md fast-path commands first before deep debugging

This ensures the documentation serves both as operational procedures (docs/BOOTSTRAP.md) and project management (docs/PLAN.md).

## Troubleshooting Priority

**Always use docs/TROUBLESHOOTING.md first** when cluster components aren't working:

1. **Fast-path health checks** - Quick status commands for all core components
2. **Known tricky components** - Proxmox CSI storage issues, SealedSecret decryption problems
3. **Common recovery actions** - Controller restarts, forced reconciliation
4. **Only then** proceed to deeper investigation if fast-path doesn't resolve the issue
