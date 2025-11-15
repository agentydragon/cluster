# Cluster Planner Skill Usage Examples

## Example 1: New Cluster with Vault + Cert-Manager + DNS

**User Request**: "I need to plan a production cluster with Vault for secrets, cert-manager for TLS, and
PowerDNS for external DNS. Help me figure out the dependencies."

**Skill Response Flow**:

### Phase 1: Scratchpad Initialization

```markdown
# CLUSTER DEPENDENCY SCRATCHPAD
*Last updated: 2024-01-15 10:30:00*

## Component Matrix
| Component | Depends On | Provides | Bootstrap Method | Deploy Type | Special Notes | Research Status |
|-----------|------------|----------|------------------|-------------|---------------|-----------------|
| Vault | TODO | TODO | TODO | TODO | TODO | PENDING |
| Cert-Manager | TODO | TODO | TODO | TODO | TODO | PENDING |
| PowerDNS | TODO | TODO | TODO | TODO | TODO | PENDING |
```text

### Phase 2: Research Agent Deployment

Skill launches research agents for each component:

**Research Agent 1 - Vault**:

- Analyzes Vault Helm chart and operator docs
- Discovers: needs storage, can start on HTTP, provides secret API
- Finds gotcha: needs manual initialization and unsealing

**Research Agent 2 - Cert-Manager**:

- Studies cert-manager CRDs and webhook requirements
- Discovers: needs DNS for validation, provides Certificate CRDs
- Finds gotcha: webhook must be ready before ClusterIssuer works

**Research Agent 3 - PowerDNS**:

- Examines PowerDNS configurations and API docs
- Discovers: needs SQLite storage, provides DNS API for cert-manager
- Finds gotcha: API key needed for cert-manager integration

### Phase 3: Scratchpad Updates

```markdown
[10:35] - RESEARCH COMPLETE: Vault
- Depends On: Persistent storage, ServiceAccount
- Provides: Secret API, PKI backend
- Bootstrap Method: HTTP mode with root token
- Deploy Type: StatefulSet (HA) or Deployment (dev)
- Special Notes: Manual init/unseal required, needs eventual HTTPS

[10:37] - RESEARCH COMPLETE: Cert-Manager
- Depends On: DNS provider API, webhook readiness
- Provides: Certificate CRDs, automatic cert renewal
- Bootstrap Method: ClusterIssuer with DNS-01 challenge
- Deploy Type: Deployment + ValidatingAdmissionWebhook
- Special Notes: Webhook MUST be ready before creating certificates

[10:40] - CIRCULAR DEPENDENCY DETECTED!
- Vault wants HTTPS from cert-manager
- Cert-manager needs DNS API from PowerDNS
- PowerDNS API key should come from Vault
```

### Phase 4: Critic Review

**Critic Agent Response**:

```text
VALIDATION RESULT: NEEDS_WORK

ISSUES FOUND:
- Critical: Circular dependency Vault→Cert-Manager→DNS→Vault
- Medium: No clear bootstrap path for PowerDNS API key
- Low: Vault initialization process not defined

SUGGESTIONS:
- Break cycle: PowerDNS starts with hardcoded bootstrap API key
- Vault starts in HTTP mode, gets HTTPS after cert-manager ready
- Use External Secrets to migrate PowerDNS to Vault-managed API key post-bootstrap

QUESTIONS TO INVESTIGATE:
- Can PowerDNS API key be rotated after migration to Vault?
- What happens if cert-manager webhook is not ready during ClusterIssuer creation?
```bash

### Phase 5: Solution & Validation

```markdown
[10:50] - SOLUTION IMPLEMENTED:
Phase 1: PowerDNS with hardcoded API key
Phase 2: Cert-Manager with PowerDNS DNS-01
Phase 3: Vault in HTTP mode
Phase 4: Vault HTTPS certificate from cert-manager
Phase 5: External Secrets migration of PowerDNS key to Vault

[10:52] - CRITIC RE-VALIDATION: PASS
- Cycle resolved through phased deployment
- Clear bootstrap path defined
- Security maintained (bootstrap key documented for rotation)
```bash

## Example 2: Adding Monitoring to Existing Cluster

**User Request**: "I want to add Prometheus and Grafana to my cluster that already has Vault and ingress.
What do I need to consider?"

**Skill Response**:

### Integration Analysis

```markdown
[11:00] - ANALYZING EXISTING CLUSTER:
- Vault: Running, provides secret management
- Ingress-Nginx: Running, provides HTTPS termination
- Cert-Manager: Running, provides TLS certificates

[11:05] - RESEARCH: Prometheus Operator
- Depends On: CRDs (ServiceMonitor, PrometheusRule)
- Provides: Metrics collection, alerting
- Special Notes: Large resource requirements, needs PVC for retention

[11:08] - RESEARCH: Grafana
- Depends On: Prometheus data source
- Provides: Dashboards, visualization
- Bootstrap Method: Default admin password → Vault-managed

[11:10] - CRITIC REVIEW REQUEST:
Plan: Add monitoring stack, store Grafana password in Vault, expose via ingress
```

**Critic Response**:

```bash
VALIDATION RESULT: NEEDS_WORK

ISSUES FOUND:
- Security: Default Grafana admin password exposure window
- Operational: No alerting rules defined
- Resource: Prometheus storage requirements not calculated

SUGGESTIONS:
- Use init container to set Grafana admin password from Vault immediately
- Define basic alerting rules for cluster health
- Calculate storage needs based on metric retention policy

IMPLEMENTATION ORDER:
1. Deploy Prometheus Operator (CRDs first)
2. Configure Vault secret for Grafana
3. Deploy Prometheus with storage
4. Deploy Grafana with Vault secret
5. Configure ingress with cert-manager
6. Import basic dashboards
```text

## Example 3: Troubleshooting Existing Dependencies

**User Request**: "My cert-manager is failing to create certificates. Can you analyze what might be wrong with my setup?"

**Skill Response**:

### Diagnostic Analysis

```markdown
[12:00] - ANALYZING CURRENT STATE:
Reading existing cluster configuration...

[12:02] - DEPENDENCY CHECK:
- Cert-Manager: Deployed
- DNS Provider: PowerDNS detected
- Webhook Status: CHECKING...

[12:05] - FOUND ISSUE:
PowerDNS kustomization status: "Unknown - Reconciliation in progress"
Cert-Manager ClusterIssuer status: "Not Ready"

[12:07] - RESEARCH AGENT: PowerDNS Status
Found: PowerDNS reconciliation stuck on production secrets
Bootstrap secret: Working
Production secret: SecretSyncError - vault-backend not ready

[12:10] - ROOT CAUSE IDENTIFIED:
Cert-Manager waiting for PowerDNS dependency
PowerDNS production secrets can't sync because Vault integration incomplete
Bootstrap PowerDNS is actually working, but Flux dependency check failing

[12:12] - CRITIC VALIDATION:
Issue: Flux dependency check too strict for bootstrap phase
Solution: Temporarily disable PowerDNS dependency in cert-manager kustomization
Validation: Cert-Manager can use working PowerDNS bootstrap API
```text

## Example 4: Security Hardening Review

**User Request**: "Review my cluster security setup - I have everything running but want to make sure it's production-ready."

**Skill Response**:

### Security Audit

```markdown
[13:00] - SECURITY REVIEW INITIATED
Components: Vault, External Secrets, Cert-Manager, Ingress, Apps

[13:05] - SECRET MANAGEMENT AUDIT:
✓ Vault: Proper HA, auto-unseal configured
✓ External Secrets: Using Vault backend
⚠ Found: Some bootstrap secrets still in plaintext
⚠ Found: Vault root token still accessible

[13:10] - RBAC AUDIT:
✓ Service accounts properly scoped
✓ ClusterRoles minimal permissions
✗ Found: Default service account has secrets access
✗ Found: Some pods running as root unnecessarily

[13:15] - NETWORK SECURITY AUDIT:
⚠ NetworkPolicies not implemented
⚠ All pods can reach all services
⚠ Ingress allows all IPs (no allowlist)

[13:20] - CRITIC SECURITY REVIEW:
VALIDATION RESULT: NEEDS_HARDENING

CRITICAL ISSUES:
- Root token accessible (revoke after setup complete)
- Default SA overprivileged
- No network segmentation

HIGH PRIORITY:
- Rotate bootstrap secrets
- Implement NetworkPolicies
- Remove root privileges where unnecessary

RECOMMENDATIONS:
1. Immediate: Revoke Vault root token, use auth methods
2. Week 1: Implement pod security standards
3. Week 2: Deploy NetworkPolicies
4. Week 3: Security scanning integration
```text

These examples show how the skill maintains context, uses research agents for deep analysis, validates
with critics, and provides actionable deployment strategies.
