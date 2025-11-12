# Claude Code Agent Instructions

## Project Documentation Strategy

This repository uses specialized documentation files for different purposes:

### docs/BOOTSTRAP.md
**Purpose**: Always describes a working bootstrap sequence from unpopulated Proxmox cluster up to where we got in cluster implementation.

**Content**:
- Step-by-step instructions for cold-starting the Talos cluster from nothing
- Complete deployment procedures (terraform, CNI, applications, external connectivity)
- Verification steps to confirm successful deployment

**Maintenance**: This document should be continuously updated to reflect the current working state. When new components are added or procedures change, docs/BOOTSTRAP.md must be updated to maintain an accurate "recipe" for reproducing the cluster.

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
- Completed features with status markers (✅)
- Remaining tasks as checkbox items ([ ])
- Design documents for planned features
- Strategic technical decisions and rationale

**Maintenance**: This document tracks the project roadmap and evolution. Completed items should be marked as done and moved to "What We Successfully Achieved" sections. New goals and tasks should be added to remaining work sections.

## Key Principles

1. **docs/BOOTSTRAP.md is always actionable** - anyone should be able to follow it and get a working cluster
2. **docs/PLAN.md is strategic** - focuses on what we're building and why
3. **Keep both in sync** - when implementation is complete, move details from docs/PLAN.md to docs/BOOTSTRAP.md
4. **Document current state accurately** - especially important for infrastructure that changes over time

## Command Execution Context

**All kubectl, talosctl, kubeseal, flux, and helm commands** assume execution from the cluster directory (direnv auto-loaded) or using `direnv exec .` prefix if run elsewhere.

This provides consistent tool versions (nix-managed) and automatic KUBECONFIG/TALOSCONFIG environment variables.

## Usage for Claude Code

When working on this cluster:

- **Before making changes**: Read docs/BOOTSTRAP.md to understand current working state
- **After completing work**: Update docs/BOOTSTRAP.md with new procedures if they change the bootstrap sequence
- **When planning**: Use docs/PLAN.md to understand goals and add new tasks
- **When finishing features**: Mark items complete in docs/PLAN.md and ensure docs/BOOTSTRAP.md reflects the new capabilities

This ensures the documentation serves both as operational procedures (docs/BOOTSTRAP.md) and project management (docs/PLAN.md).