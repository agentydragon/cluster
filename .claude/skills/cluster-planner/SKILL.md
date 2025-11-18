---
name: cluster-planner
description: Expert Kubernetes cluster dependency planner that researches components, maintains live dependency scratchpads, detects circular dependencies, validates plans with critic agents, and creates reliable bootstrap strategies for complex production clusters
allowed-tools: ["*"]
---

# Kubernetes Cluster Planner Skill

Systematically plans complex Kubernetes cluster deployments using Google SRE methodology,
maintaining live dependency tracking, deep component research via source code analysis,
and critic-agent validation for reliable production deployments.

## Core Capabilities

### Multi-Scratchpad Management

- **Activity Log**: Append-only chronological record of all actions and discoveries
- **Dependency Matrix**: Live-updated component dependency tracking
- **Component Checklists**: Generated validation lists per component class
- **Troubleshooting Playbooks**: Fast-path debugging with source code analysis

### Research & Validation System

- **Research Agents**: Deep-dive into docs, source code, Helm charts, CRDs
- **Critic Agents**: Security, operational, integration, reliability validation
- **Pitfall Detection**: Common Kubernetes deployment traps and solutions
- **Bootstrap Strategy**: Handles circular dependencies through phased rollouts

## Methodology: Google SRE-Inspired

### SRE Principles Applied

- **SLO-Driven Planning**: Define reliability targets before deployment
- **Error Budget Planning**: Plan acceptable failure rates during rollout
- **Toil Reduction**: Automate everything possible
- **Gradual Change**: Phased rollouts with validation gates
- **System Design Focus**: Analyze failure modes, design for resilience
- **Monitoring Day 1**: Observability before applications

### 4-Phase Process

1. **Initialize**: Create scratchpads, analyze current state
2. **Research**: Deep component analysis via specialized agents
3. **Validate**: Critic review of all plans and dependencies
4. **Deploy**: Sequenced rollout with health checks and rollback

## Component Classes Supported

### Infrastructure

- **CNI**: Cilium, Calico, Flannel (bootstrap paradox handling)
- **Storage**: Longhorn, Rook/Ceph, local-path (chicken-egg resolution)
- **Load Balancers**: MetalLB, cloud providers, HAProxy

### Security & Secrets

- **Secret Management**: Vault, External Secrets, Sealed Secrets
- **Certificate Management**: cert-manager, Spiffe/Spire
- **DNS Providers**: PowerDNS, CoreDNS, External DNS

### Platform Services

- **Ingress**: nginx, Traefik, HAProxy, Istio Gateway
- **Monitoring**: Prometheus, Grafana, Jaeger, ELK Stack
- **Service Mesh**: Istio, Linkerd, Consul Connect

### Applications

- **CI/CD**: Tekton, Argo, Jenkins, GitLab Runner
- **Databases**: PostgreSQL, MySQL, Redis, MongoDB operators
- **SSO/Auth**: Authentik, Keycloak, Dex

## Source Code Analysis Protocol

### Automatic Repository Management

Clones and analyzes source code using `/code/domain.tld/org/repo` structure:

```bash
# Auto-discovery of configuration options
find repo -path "*/cmd/*" -name "*.go"        # CLI flags
rg "flag\.|config\.|env\." --type go          # Config options
rg "log.*level|debug|trace" --type go         # Debug options
rg "health|metrics|pprof" --type go          # Endpoints
```

### Fast-Path Troubleshooting

When components fail:

1. Clone source code if not exists
2. Identify debug flags and health endpoints
3. Enable verbose logging via patches
4. Analyze failure patterns from logs
5. Update scratchpads with findings

## Usage Patterns

### New Cluster Planning

"Plan production cluster with Vault, cert-manager, PowerDNS, monitoring"

- Initializes comprehensive dependency analysis
- Detects circular dependencies (Vault→HTTPS→DNS→Vault)
- Designs bootstrap sequence with temporary configurations
- Provides migration path to production setup

### Existing Cluster Enhancement

"Add monitoring stack to cluster with existing Vault and ingress"

- Analyzes current cluster state via kubectl/terraform
- Identifies integration points and potential conflicts
- Plans incremental rollout strategy
- Validates with critic agents before implementation

### Dependency Troubleshooting

"Cert-manager failing to create certificates, analyze dependencies"

- Rapid health assessment via component-specific commands
- Source code analysis for configuration options
- Identifies root cause (e.g., PowerDNS dependency not ready)
- Provides specific remediation steps

## Critical Pitfalls Prevented

### Infrastructure Bootstrap

- CNI managed by operator that requires CNI (static manifests solution)
- Storage operator needs PVC but provides storage (local-path bootstrap)
- LoadBalancer services pending without MetalLB (deployment ordering)

### Timing & Dependencies

- Creating CRs before CRDs exist (explicit wait conditions)
- Webhook not ready before dependent resources (readiness verification)
- Secret circular dependencies (bootstrap + migration strategy)

### Security & RBAC

- Default ServiceAccount with cluster-admin (least privilege SAs)
- Hardcoded secrets in manifests (External Secrets integration)
- Pod security policy violations (securityContext validation)

## Success Criteria

A plan is complete when:

- All components researched with real requirements documented
- No unresolved circular dependencies
- Bootstrap sequence critic-validated
- Failure scenarios considered and mitigated
- Health checks and rollback procedures defined
- Full destroy→recreate→verify cycle passes

## Integration Features

- Reads existing k8s manifests and Terraform configurations
- Follows project-specific constraints from CLAUDE.md
- Updates GitOps repositories with validated configurations
- Provides exact commands for health checks and rollbacks
- Maintains audit trail of all decisions and changes

This skill embodies 20 years of Google SRE experience: measure what matters,
plan for failure, automate everything, and always have a way back.
