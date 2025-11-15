# Cluster Planner Methodology

## Core Workflow

The cluster-planner skill follows a rigorous methodology to ensure reliable, secure, and maintainable cluster deployments.

## Phase 1: Initialization & Discovery

### Scratchpad Creation

```
1. Initialize scratchpad from template
2. Populate known components with TODO placeholders
3. Set session timestamp and ID
4. Commit initial state to track progress
```

### Current State Analysis

```
1. Scan existing cluster (if any) for deployed components
2. Read terraform/k8s manifests to understand current architecture
3. Identify what's working vs what needs deployment
4. Update scratchpad with current state
```

### Scope Definition

```
1. Clarify user requirements and constraints
2. Identify target components for deployment
3. Map business requirements to technical components
4. Set success criteria and validation checkpoints
```

## Phase 2: Deep Research Protocol

### Component Research Agent Deployment

For each component, launch specialized research agent with this protocol:

```
RESEARCH AGENT MISSION:
Component: [name]
Priority: [critical/high/medium/low]
Timeline: [immediate/planned/future]

INVESTIGATION CHECKLIST:
□ Official documentation analysis
□ Helm chart/operator source code review
□ CRD and API specification study
□ GitHub issues/discussions for gotchas
□ Version compatibility matrix
□ Environmental dependency mapping
□ Security and RBAC requirements
□ Performance and scaling characteristics
□ Backup and disaster recovery needs
□ Monitoring and observability setup

DELIVERABLE:
Structured component profile with dependencies, provides, gotchas, and deployment strategy
```

### Research Validation Protocol

```
1. Each research result reviewed for completeness
2. Cross-reference findings with multiple sources
3. Flag uncertainty areas for additional investigation
4. Update scratchpad with timestamped findings
5. Highlight any surprises or gotchas discovered
```

## Phase 3: Dependency Analysis Engine

### Dependency Graph Construction

```
1. Parse research results into dependency relationships
2. Distinguish startup vs runtime vs configuration dependencies
3. Build directed graph representation
4. Weight edges by dependency criticality
```

### Circular Dependency Detection

```
ALGORITHM:
1. Run topological sort on dependency graph
2. If sort fails, cycles exist - identify shortest cycles
3. For each cycle, analyze dependency nature:
   - Hard startup dependency (must resolve)
   - Soft runtime dependency (can defer)
   - Configuration dependency (can bootstrap)
4. Generate resolution strategies for each cycle type
```

### Bootstrap Strategy Generation

```
FOR EACH CIRCULAR DEPENDENCY:
1. Identify which component can start with minimal config
2. Design temporary/bootstrap configuration
3. Plan migration path from bootstrap to production
4. Validate migration is secure and reversible
5. Document rollback procedures
```

## Phase 4: Critic Validation Framework

### Multi-Agent Critic Review

Each proposed solution gets reviewed by specialized critic agents:

```
SECURITY CRITIC:
- Reviews secret management approach
- Validates RBAC and network security
- Checks for privilege escalation risks
- Ensures secrets rotation capability

OPERATIONAL CRITIC:
- Reviews deployment complexity
- Validates health check strategies
- Checks failure scenario handling
- Ensures debugging capability

INTEGRATION CRITIC:
- Reviews component interaction patterns
- Validates version compatibility
- Checks resource contention
- Ensures upgrade path viability

RELIABILITY CRITIC:
- Reviews single points of failure
- Validates backup and recovery
- Checks disaster recovery procedures
- Ensures monitoring coverage
```

### Critic Feedback Integration

```
1. Collect all critic feedback
2. Categorize issues by severity (critical/high/medium/low)
3. For critical/high issues:
   - Research alternative approaches
   - Redesign problematic parts
   - Re-submit for critic validation
4. For medium/low issues:
   - Document as known limitations
   - Plan future improvement iterations
5. Update scratchpad with critic outcomes
```

## Phase 5: Deployment Strategy Synthesis

### Phase Planning

```
PHASE STRUCTURE:
Phase 1: Foundation (no external dependencies)
Phase 2: Infrastructure (storage, networking)
Phase 3: Security (authentication, secrets)
Phase 4: Platform (DNS, monitoring, logging)
Phase 5: Applications (actual workloads)

FOR EACH PHASE:
1. List components in dependency order
2. Define phase completion criteria
3. Specify validation commands
4. Document rollback procedures
5. Estimate deployment timeline
```

### Health Check Strategy

```
COMPONENT LEVEL:
- Pod readiness and liveness probes
- Service endpoint availability
- API response validation
- Resource utilization checks

INTEGRATION LEVEL:
- Cross-component connectivity
- Secret access verification
- Certificate validity checks
- DNS resolution validation

SYSTEM LEVEL:
- End-to-end workflow testing
- Performance baseline establishment
- Security posture validation
- Backup/restore verification
```

## Phase 6: Documentation & Handoff

### Scratchpad Finalization

```
1. Remove all TODO placeholders
2. Ensure all components researched and planned
3. Validate dependency graph is acyclic
4. Confirm all critic reviews passed
5. Document final deployment sequence
6. Include troubleshooting guidance
```

### Operational Documentation

```
DELIVERABLES:
1. Updated cluster-dependency-scratchpad.md
2. Deployment runbook with exact commands
3. Health check and validation procedures
4. Rollback procedures for each phase
5. Post-deployment security hardening checklist
6. Monitoring and alerting recommendations
```

## Error Recovery Protocols

### Research Failure Recovery

```
IF research agent fails or returns incomplete data:
1. Log the failure with context
2. Try alternative research approaches
3. Escalate to manual investigation if needed
4. Document uncertainty in scratchpad
5. Flag for human review before proceeding
```

### Critic Validation Failure Recovery

```
IF critic repeatedly rejects a plan:
1. Analyze common failure patterns
2. Research industry best practices
3. Consider alternative architectures
4. Escalate to human architect review
5. Document limitations and trade-offs
```

### Circular Dependency Resolution Failure

```
IF no resolution found for circular dependencies:
1. Question necessity of each dependency
2. Research if components can operate degraded
3. Consider alternative component selections
4. Design manual intervention procedures
5. Document operational complexity trade-offs
```

## Quality Gates

### Research Quality Gate

- [ ] All components have complete research profiles
- [ ] No critical unknowns remain unresolved
- [ ] Version compatibility verified
- [ ] Environmental requirements documented

### Design Quality Gate

- [ ] No unresolved circular dependencies
- [ ] Bootstrap strategy for each component defined
- [ ] Security review passed
- [ ] Operational complexity acceptable

### Validation Quality Gate

- [ ] All critic reviews passed or issues documented
- [ ] Deployment sequence validated
- [ ] Rollback procedures tested
- [ ] Health checks defined and validated

### Handoff Quality Gate

- [ ] Complete documentation delivered
- [ ] No TODOs remain in scratchpad
- [ ] Human review completed (if required)
- [ ] Deployment ready with clear next steps

## Continuous Improvement

### Feedback Collection

```
1. Track which research sources were most valuable
2. Monitor critic accuracy and usefulness
3. Measure actual vs predicted deployment complexity
4. Document lessons learned from failures
5. Update methodology based on experience
```

### Methodology Evolution

```
1. Regular review of agent prompt effectiveness
2. Update component research checklists
3. Refine critic validation criteria
4. Improve circular dependency resolution strategies
5. Enhance documentation templates
```
