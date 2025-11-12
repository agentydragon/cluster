# Claude Code Agent Instructions

## Project Documentation Strategy

This repository uses specialized documentation files for different purposes:

### BOOTSTRAP.md
**Purpose**: Always describes a working bootstrap sequence from unpopulated Proxmox cluster up to where we got in cluster implementation.

**Content**:
- Step-by-step instructions for cold-starting the Talos cluster from nothing
- Complete deployment procedures (terraform, CNI, applications)
- Node management operations (add/remove/restart)
- Troubleshooting common issues with specific symptoms and solutions
- Current working cluster status and configuration details

**Maintenance**: This document should be continuously updated to reflect the current working state. When new components are added or procedures change, BOOTSTRAP.md must be updated to maintain an accurate "recipe" for reproducing the cluster.

### PLAN.md
**Purpose**: Describes high-level goals we want to implement, lists what we finished, and what remains to be done as items.

**Content**:
- Project overview and architecture decisions
- Completed features with status markers (✅)
- Remaining tasks as checkbox items ([ ])
- Design documents for planned features
- Strategic technical decisions and rationale

**Maintenance**: This document tracks the project roadmap and evolution. Completed items should be marked as done and moved to "What We Successfully Achieved" sections. New goals and tasks should be added to remaining work sections.

## Key Principles

1. **BOOTSTRAP.md is always actionable** - anyone should be able to follow it and get a working cluster
2. **PLAN.md is strategic** - focuses on what we're building and why
3. **Keep both in sync** - when implementation is complete, move details from PLAN.md to BOOTSTRAP.md
4. **Document current state accurately** - especially important for infrastructure that changes over time

## Command Execution Context

**All kubectl, talosctl, kubeseal, and flux commands** in this repository documentation assume execution within the cluster's direnv environment. Commands should be run either:

1. From `/home/agentydragon/code/cluster/` directory (direnv auto-loaded)
2. Using `direnv exec .` prefix if not in the directory

This provides consistent tool versions (nix-managed) and automatic KUBECONFIG/TALOSCONFIG environment variables.

## Usage for Claude Code

When working on this cluster:

- **Before making changes**: Read BOOTSTRAP.md to understand current working state
- **After completing work**: Update BOOTSTRAP.md with new procedures if they change the bootstrap sequence
- **When planning**: Use PLAN.md to understand goals and add new tasks
- **When finishing features**: Mark items complete in PLAN.md and ensure BOOTSTRAP.md reflects the new capabilities

This ensures the documentation serves both as operational procedures (BOOTSTRAP.md) and project management (PLAN.md).