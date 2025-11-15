---
name: cluster-planner
description: Expert Kubernetes cluster dependency planner that researches components, maintains live dependency scratchpads, detects circular dependencies, validates plans with critic agents, and creates reliable bootstrap strategies for complex production clusters
allowed-tools: ["*"]
---

# Kubernetes Cluster Planner Skill

This skill systematically plans complex Kubernetes cluster deployments by maintaining a live dependency scratchpad, researching component requirements through source code analysis, and validating plans with critic agents.

## Core Capabilities

### 1. Multi-Scratchpad Management

- **Activity Log** (`cluster-activity-log.md`): Append-only log of all actions, discoveries, errors, commands
- **Dependency Matrix** (`cluster-dependency-scratchpad.md`): Always current view of component dependencies
- **Per-Component Checklists**: Generated validation checklists for each component
- Records discoveries and updates with timestamps across all scratchpads
- Maintains circular dependency alerts and resolution strategies

### 2. Deep Component Research

- Delegates research to specialized agents for each component
- Analyzes Helm charts, operator documentation, CRDs
- Discovers real deployment requirements, gotchas, and edge cases
- Updates scratchpad with research findings

### 3. Plan Validation & Criticism

- Every proposed change/solution gets critic agent review
- Critic agents check for overlooked dependencies, security issues, operational concerns
- Iterates on plans until critic validation passes
- Documents validation outcomes in scratchpad

### 4. Bootstrap Strategy Design

- Separates bootstrap vs production configurations
- Handles chicken-egg problems (Vault needs HTTPS, HTTPS needs certs, certs need DNS)
- Creates phased deployment sequences
- Plans secret management transitions

## Methodology

### Phase 1: Initialize Multi-Scratchpad System

Creates comprehensive planning system with multiple interconnected documents:

```markdown
# ACTIVITY LOG - append-only chronological record
# DEPENDENCY SCRATCHPAD - live dependency matrix
# COMPONENT CHECKLISTS - per-component validation lists
# TROUBLESHOOTING PLAYBOOK - fast-path debugging
```

### Phase 2: Google SRE-Inspired Methodology

Applies battle-tested SRE principles adapted for cluster planning:

**SLO-Driven Planning**: Define reliability targets before deployment
**Error Budget Planning**: Plan for acceptable failure rates during rollout
**Toil Reduction**: Automate everything that can be automated
**Gradual Change**: Phased rollouts with validation at each step
**System Design Focus**: Analyze failure modes and design for resilience
**Monitoring from Day 1**: Observability before applications

### Phase 3: Systematic Research

For each component:

1. **Research Agent**: Analyzes docs/charts/CRDs to understand real requirements
2. **Update Scratchpad**: Records findings with timestamps
3. **Dependency Analysis**: Maps what it needs vs what it provides
4. **Bootstrap Strategy**: Determines how to start with minimal deps

### Phase 3: Critic Validation

Before finalizing any plan:

1. **Critic Agent Review**: "Here's my plan for component X, what could go wrong?"
2. **Dependency Validation**: Check for cycles, missing deps, timing issues
3. **Security Review**: Ensure proper secret handling, RBAC, network policies
4. **Operational Review**: Consider failure scenarios, upgrade paths, scaling

### Phase 4: Deployment Sequence

1. **Topological Sort**: Arrange components in valid dependency order
2. **Phase Planning**: Group into bootstrap/infrastructure/platform/application layers
3. **Validation Commands**: Provide health checks for each phase
4. **Rollback Strategy**: Document how to revert each phase

## Usage Patterns

### New Cluster Planning

Invoke when planning a greenfield Kubernetes cluster with multiple components like:

- Storage (Longhorn, Rook, local-path)
- Networking (CNI, MetalLB, Ingress)
- Security (Vault, cert-manager, External Secrets, RBAC)
- Platform (DNS, monitoring, logging)
- Applications (SSO, Git, registries, CI/CD)

### Existing Cluster Enhancement

Invoke when adding major components to existing clusters where dependency analysis is critical.

### Troubleshooting Circular Dependencies

Invoke when deployment order is unclear or components have chicken-egg problems.

## Research Methodology

The skill uses specialized research agents:

### Component Research Agent

- Reads official documentation
- Analyzes Helm chart values and templates
- Studies operator CRDs and controllers
- Identifies runtime vs startup dependencies
- Discovers bootstrap modes and limitations

### Gotcha Detection Agent

- Looks for known issues in GitHub issues/discussions
- Analyzes deployment guides for warnings
- Identifies version-specific problems
- Maps environmental dependencies (node features, kernel modules)

### Security Review Agent

- Validates secret management strategies
- Checks RBAC requirements
- Identifies network policy needs
- Reviews privilege escalation paths

## Critic Agent Prompts

When validating plans, the skill uses structured critic prompts:

```
CRITIC REVIEW REQUEST:
Component: [name]
Proposed Solution: [description]
Dependencies Identified: [list]
Bootstrap Strategy: [method]

Please review for:
- Missing dependencies
- Circular dependency risks
- Security vulnerabilities
- Operational gotchas
- Alternative approaches
- Failure scenarios

Focus especially on: [specific concerns]
```

## Success Criteria

A plan is complete when:

- [ ] All components researched with real requirements documented
- [ ] No circular dependencies exist or are properly resolved
- [ ] Bootstrap sequence validated by critic agents
- [ ] Failure scenarios considered and mitigated
- [ ] Secret management strategy is secure and practical
- [ ] Deployment sequence has been critic-validated
- [ ] Health checks and validation commands provided

## Integration with Cluster Codebase

The skill integrates with existing cluster code by:

- Reading current k8s manifests to understand existing components
- Analyzing Terraform configurations for infrastructure dependencies
- Checking Flux kustomizations for deployment patterns
- Reviewing CLAUDE.md for project-specific constraints

## Error Recovery

When plans fail critic validation:

1. Document the criticism in scratchpad
2. Research the identified issues
3. Revise the plan addressing critic concerns
4. Re-submit for critic validation
5. Iterate until validation passes

The skill maintains a history of failed approaches to avoid repeating mistakes.
