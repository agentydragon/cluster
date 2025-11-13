# `/analyze-dependencies [service-pattern]`

Perform comprehensive dependency analysis for Kubernetes services and deployments to identify explicit vs implicit dependencies.

## Command Usage

**Parameters:**

- `service-pattern` (optional): pattern or set of services. If omitted, analyzes all services.

**Examples:**

```bash
/analyze-dependencies  # Analyze all services
/analyze-dependencies powerdns                    # Specific service
/analyze-dependencies storage and network layers  # Free-form specification
```

## Operation

### 1. Discovery Phase

- Scan `k8s/` directory for all Flux resources:
  - HelmReleases (`helmrelease.yaml`)
  - Kustomizations (`*kustomization*.yaml`)
  - Direct Kubernetes manifests
- Filter by pattern if provided
- Identify service types and layers

### 2. Dependency Analysis (Open-Ended Reasoning)

**Use your full capabilities and intelligence to discover and analyze ALL relevant dependency relationships**.
This includes but is not limited to:

#### Known Specific Dependency Types

- **VIP Assignment**: MetalLB LoadBalancer IP allocation (10.0.3.x ranges)
- **CNI/Networking**: Cilium pod networking, kube-proxy replacement
- **Upstream Services**: Service-to-service communications, API dependencies
- **DNS Resolution**: PowerDNS, external DNS, cluster DNS
- **Certificate Dependencies**: cert-manager, Let's Encrypt, PowerDNS webhook
- **Storage**: PVCs, storage classes, persistent data
- **Load Balancing**: MetalLB speaker/controller, IPAddressPools, L2Advertisement
- **Ingress**: NGINX ingress controller, ingress classes, routing rules

- **Security**: RBAC, service accounts, secrets, network policies
- **External Services**: VPS connectivity, Tailscale VPN, internet access

##### Runtime Dependencies

- Kubernetes API server availability
- etcd cluster health
- Node scheduling and resource availability
- Container runtime (containerd)

- Image registry access
- Network connectivity (internal/external)
- Storage backend availability

##### Deployment Dependencies

- Namespace existence and RBAC
- CRD installation and versions

- Operator/controller readiness
- Init containers and job completion
- Resource quotas and limits
- Pod security policies/standards

##### Configuration

- ConfigMaps and environment variables

- Secrets and credential management
- Service discovery and endpoints
- Network policies and firewall rules
- Ingress rules and TLS certificates
- Monitoring and logging configuration

##### External Systems

- VPS nginx proxy configuration
- Route 53 DNS delegation
- Let's Encrypt ACME servers
- Container registries (Docker Hub, etc.)
- GitHub/Git repository access
- Tailscale/Headscale mesh connectivity

**Agent Instructions:**

- **Reason deeply** about each service's operational requirements

- **Trace data flows** and communication paths between components
- **Identify hidden dependencies** not explicitly declared
- **Consider failure scenarios** and cascade effects

- **Examine configuration files** for implicit requirements
- **Analyze network patterns** and port dependencies
- **Check for timing dependencies** and race conditions
- **Discover external integrations** and third-party services

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

For each entity, report dependencies grouped by type and verification status:

```markdown
## Service: [SERVICE_NAME]
**Type:** [HelmRelease|Kustomization|Deployment]
**Namespace:** [NAMESPACE]
**Layer:** [Core|Platform|Security|Applications]
**Files Analyzed:** [LIST_OF_CONFIG_FILES]

#### Infrastructure Dependencies
- ✅ **[DEPENDENCY]**: [DETAILED_REASON] - *Explicitly checked via [METHOD]*
- ❌ **[DEPENDENCY]**: [DETAILED_REASON] - *NOT checked*
- ⚠️  **[DEPENDENCY]**: [DETAILED_REASON] - *Partially checked via [METHOD]*

#### Service Dependencies
- ✅ **[DEPENDENCY]**: [DETAILED_REASON] - *Explicitly checked via [METHOD]*
- ❌ **[DEPENDENCY]**: [DETAILED_REASON] - *NOT checked*

#### External Dependencies
- ✅ **[DEPENDENCY]**: [DETAILED_REASON] - *Explicitly checked via [METHOD]*
- ❌ **[DEPENDENCY]**: [DETAILED_REASON] - *NOT checked*

#### Hidden/Implicit Dependencies Discovered
- ❌ **[HIDDEN_DEP]**: [ANALYSIS_OF_WHY_NEEDED] - *Discovered via [REASONING_METHOD]*

### Dependency Chain Analysis
[SERVICE] → [IMMEDIATE_DEP] → [TRANSITIVE_DEP] → [ROOT_DEP]

### Data Flow Analysis
*Reasoning about how data/requests flow through dependencies*

### Failure Cascade Analysis
*Reasoning about what happens when each dependency fails*

### Risk Assessment
- **Critical Risk**: [COUNT] unchecked dependencies that cause service failure
- **High Risk**: [COUNT] unchecked dependencies that cause degradation
- **Medium Risk**: [COUNT] partially checked dependencies
- **Low Risk**: [COUNT] fully verified dependencies

### Specific Recommendations (Prioritized)

1. **CRITICAL**: Add explicit check for [DEP] because [FAILURE_IMPACT]
2. **HIGH**: Implement health check for [DEP] via [SPECIFIC_METHOD]
3. **MEDIUM**: Consider timeout/retry for [DEP] to handle [SPECIFIC_SCENARIO]
```

### Global Cluster Report

After analyzing all services, provide:

- Cross-service dependency matrix

- Cluster-wide single points of failure
- Dependency cycles and circular dependencies
- Overall cluster resilience assessment

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

1. **Individual Service Reports**: Detailed dependency analysis per service
2. **Cluster-wide Dependency Graph**: Visual representation of all dependencies
3. **Gap Analysis**: Prioritized list of missing dependency checks
4. **Implementation Plan**: Specific steps to add missing verifications

This command provides comprehensive visibility into service dependencies and ensures reliable cluster operations.
