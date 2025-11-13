# `/validate-deployment-ordering [service-pattern]`

Validate zero-state deployment ordering to catch "terraform apply" breaking issues like CRD usage before
installation, circular dependencies, and layer violations.

## Command Usage

**Parameters:**

- `service-pattern` (optional): pattern or set of services. If omitted, analyzes all services.

**Examples:**

```bash
/validate-deployment-ordering  # Check entire cluster for ordering issues
/validate-deployment-ordering cert-manager        # Specific component
/validate-deployment-ordering applications        # Focus on application layer
```

## Operation

### 1. Discovery Phase

- Scan `k8s/` directory for all Flux resources:
  - HelmReleases (`helmrelease.yaml`)
  - Kustomizations (`*kustomization*.yaml`)
  - Direct Kubernetes manifests
- Filter by pattern if provided
- Identify service types and layers

### 2. Zero-State Deployment Validation

**Focus on catching the "obvious foot-guns" that break `terraform apply` from clean Proxmox state.**

#### Primary Failure Patterns to Detect

##### CRD Usage Before Installation

- **MetalLB CRDs**: IPAddressPool, L2Advertisement resources before MetalLB helm chart
- **cert-manager CRDs**: ClusterIssuer, Certificate before cert-manager installation
- **external-secrets CRDs**: ExternalSecret, ClusterSecretStore before external-secrets controller
- **Custom CRDs**: Any `apiVersion: *.io/*` resource before CRD installation

##### Layer Ordering Violations

- **Platform resources before infrastructure**: IPAddressPools before MetalLB controller
- **Applications before platform**: Services before ingress controller
- **Resources before CRD installation**: Any custom resource before its CRD

##### Circular Dependencies Requiring Multi-Stage Deploy

- **Vault ↔ Authentik**: Bootstrap credentials vs OIDC integration
- **cert-manager ↔ Services**: Certificate chicken-and-egg problems
- **DNS ↔ Certificates**: DNS-01 challenges requiring DNS service

##### Missing Explicit Dependencies

- **Applications missing external-secrets dependency**: ExternalSecret usage without controller dependency
- **Health checks on non-existent resources**: Checking resources before they can exist
- **Flux dependsOn gaps**: Missing explicit ordering between related services

##### Monolithic Dependencies (Anti-Pattern)

- **Over-broad layer dependencies**: Services depending on entire "core" layer when only needing 2 components
- **Unnecessary coupling**: Components forced to wait for unrelated services in same layer
- **Deployment bottlenecks**: Single large dependency blocking multiple independent services

**Agent Instructions:**

- **Trace deployment ordering** through kustomization.yaml resource lists
- **Verify CRD installation timing** relative to custom resource usage
- **Identify bootstrap sequencing issues** that prevent cold-start deployment
- **Check Flux dependsOn chains** for gaps and circular references
- **Flag monolithic dependencies** where services depend on entire layers instead of specific components
- **Recommend dependency splitting** to reduce coupling and improve parallel deployment

### 3. Dependency Verification

Check for explicit dependency management:

#### Flux Dependencies

- `dependsOn` in HelmReleases
- `dependsOn` in Kustomizations
- `healthChecks` for resource readiness

#### Kubernetes Dependencies

- `initContainers` for pre-requisites
- Readiness/liveness probes
- Pod disruption budgets
- Resource quotas/limits

#### External Dependencies

- Network connectivity tests
- DNS resolution checks
- Certificate validation

### 4. Output Format

**Focus on deployment-breaking issues, not operational monitoring.**

```markdown
# 🚨 CRITICAL: CRD Usage Before Installation

## [CRD_FAMILY] - Used before installation
**Problem**: [DESCRIPTION_OF_CRD_BEFORE_CHART]

**Locations using CRDs**:
- `path/file.yaml:line` - Resource type and usage context

**CRD Installation**: [WHERE_CRDS_GET_INSTALLED]

**Deployment Order Problem**:
[CURRENT_BAD_ORDER_EXPLANATION]

**Fix**: [SPECIFIC_SOLUTION]

---

# 🔥 CRITICAL: Circular Dependencies

## [SERVICE_A] ↔ [SERVICE_B] Bootstrap Circle
**Problem**: [DESCRIPTION_OF_CIRCULAR_DEPENDENCY]

**Current approach**: [HOW_ITS_HANDLED_NOW]
**Recommended**: [MULTI_STAGE_OR_BOOTSTRAP_SOLUTION]

---

# 🟡 LAYER ORDERING VIOLATIONS

## [PROBLEM_DESCRIPTION]
**Current order**: [BAD_ORDER_WITH_LINE_REFS]
**Should be**: [CORRECT_ORDER_WITH_EXPLANATION]
**Impact**: [WHAT_BREAKS_ON_COLD_START]

---

# ❌ MISSING EXPLICIT DEPENDENCIES

## [SERVICE] missing [DEPENDENCY_TYPE] dependency
**Problem**: [WHAT_RESOURCE_IS_USED_WITHOUT_DEPENDENCY]
**Files**: [FILE_REFERENCES]
**Fix**: [SPECIFIC_DEPENDENCY_TO_ADD]

---

# 🔀 MONOLITHIC DEPENDENCY ANTI-PATTERNS

## [SERVICE] depends on entire [LAYER] instead of specific components
**Problem**: [SERVICE] depends on "[LAYER]" containing [N] services but only needs [SPECIFIC_SERVICES]
**Impact**: Unnecessary deployment coupling and serialization
**Current**: `dependsOn: - name: [LAYER]`
**Recommended**: Split into specific dependencies:
```yaml
dependsOn:
  - name: [SPECIFIC_SERVICE_1]
  - name: [SPECIFIC_SERVICE_2]
```

```yaml

### 5. Prioritized Fix List

**Focus on what will immediately break zero-state deployment:**

## CRITICAL (Fix Before Next Deploy)
1. **CRD ordering issues** - Will cause immediate failure
2. **Layer violations** - Resources created before controllers exist
3. **Circular bootstraps** - Prevent successful cold-start

## HIGH (Fix Soon)
1. **Missing explicit dependencies** - Race conditions on deploy
2. **Health checks on missing resources** - Deployment hangs

## MEDIUM (Optimization)
1. **Monolithic dependencies** - Break up over-broad layer dependencies for better parallelism
2. **Dependency chain improvements** - Better reliability

## Analysis Categories

### Core Infrastructure

- **Cilium CNI**: Pod networking, kube-proxy replacement
- **MetalLB**: LoadBalancer VIP assignment
- **Storage**: PVC provisioning, storage classes

### Platform Services

- **Ingress Controllers**: External traffic routing
- **DNS Services**: Internal/external name resolution
- **Certificate Management**: TLS certificate provisioning

### Security Services

- **RBAC**: Service account permissions
- **Secret Management**: Credential storage/rotation
- **Network Policies**: Traffic segmentation

### Application Services

- **Databases**: Data persistence layers
- **Caches**: Performance optimization
- **Monitoring**: Observability stack

## Implementation Notes

### Discovery Methods

1. **File System Scan**: Find all `*.yaml` files in `k8s/`
2. **YAML Parsing**: Extract resource metadata and specifications
3. **Reference Analysis**: Follow `dependsOn`, service references, volume mounts
4. **Network Analysis**: Trace service-to-service communications

### Dependency Types

- **Explicit**: Declared in `dependsOn`, `healthChecks`

- **Implicit**: Required but not declared (networking, storage)
- **External**: Outside cluster (DNS, internet, VPS)
- **Runtime**: Only checked during operation (probes, metrics)

### Risk Classification

- **Critical**: Service cannot start without dependency
- **Important**: Service degrades without dependency
- **Optional**: Service functions with reduced capability

### Verification Methods

- **Flux dependsOn**: Deployment ordering
- **Kubernetes healthChecks**: Resource availability
- **Custom probes**: Application-specific checks
- **External validation**: Network/DNS/certificate tests

## Expected Outputs

1. **Critical CRD Issues**: Resources used before CRD installation
2. **Layer Ordering Violations**: Components deployed in wrong sequence
3. **Circular Dependencies**: Bootstrap chicken-and-egg problems
4. **Missing Dependencies**: Flux dependsOn gaps causing race conditions
5. **Prioritized Fix List**: What to fix first for successful zero-state deployment

This command prevents "oops, I forgot X depends on Y" deployment failures and ensures reliable
`terraform apply` from clean Proxmox state.
