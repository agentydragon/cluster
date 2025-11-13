# `/lint [pattern]`

Analyze GitOps repository organization, structure, and file management to ensure clean, maintainable,
and logically organized codebase.

## Command Usage

**Parameters:**

- `pattern` (optional): directory pattern or component name. If omitted, scans entire k8s/ directory.

**Examples:**

```bash
/lint                    # Scan entire k8s/ directory
/lint applications       # Scan applications directory only
/lint authentik          # Scan specific component
```

## Operation

**Primary Focus**: Repository organization, file structure, and codebase maintainability. Act as expert
GitOps repository architect focused on clean organization patterns.

### Repository Organization Analysis

#### Deep Structural Review

**Agent Instructions:**

- **Focus primarily on repository organization and structure quality**
- **Evaluate file/directory layout for logical grouping and discoverability**
- **Assess naming consistency, clarity, and convention adherence**
- **Identify organizational debt and structural anti-patterns**
- **Think like a senior developer reviewing codebase architecture for maintainability**

**Primary Analysis Areas:**

1. **Directory Structure Logic**: Hierarchical organization, component grouping, nesting depth
2. **File Naming Patterns**: Consistency, clarity, redundancy, convention adherence
3. **Resource Organization**: Related resource grouping, separation of concerns
4. **Reference Management**: Clean cross-component references, minimal coupling
5. **Structural Consistency**: Organization pattern consistency across components

**Secondary Analysis (if organizationally relevant):**

- Dependency relationships affecting repository structure
- Configuration management organization and patterns
- Documentation and metadata file placement

### 1. File Structure Consistency

#### Naming Convention Violations

- **Redundant prefixes**: Files like `authentik-config.yaml` in `authentik/` directory
- **Inconsistent object naming**: Mix of `helmrelease.yaml` vs `release.yaml` for HelmRelease resources
- **Inconsistent pluralization**: `secret.yaml` vs `secrets.yaml` naming patterns

**Agent Instructions:**

- Flag files with redundant directory-name prefixes
- Ensure consistent naming for same resource types across components
- Report mixed singular/plural naming within same component

#### Missing Standard Files

- **Missing kustomization.yaml**: Every directory should have resource orchestration
- **Missing flux-kustomization.yaml**: Components should have Flux orchestration
- **Orphaned resources**: YAML files not referenced in any kustomization.yaml

#### Duplicate or Conflicting Files

- **Duplicate resource definitions**: Same resource in multiple files
- **Conflicting configurations**: Same resource with different specs
- **Abandoned files**: Old files not cleaned up after refactoring

### 2. Reference Integrity

#### Broken Kustomization References

- **Missing files**: Resources listed in kustomization.yaml that don't exist
- **Wrong file paths**: Relative paths that don't resolve
- **Circular references**: Components depending on each other

#### Flux Dependency Issues

- **Missing dependsOn**: Components using resources without declaring dependencies
- **Invalid dependency targets**: dependsOn referencing non-existent Flux resources
- **Circular dependencies**: A depends on B depends on A

#### Resource Reference Problems

- **Missing ConfigMaps/Secrets**: Resources referenced but not defined
- **Namespace mismatches**: Resources in wrong namespaces
- **Service/Ingress target mismatches**: Services referenced that don't exist

### 3. GitOps Best Practices

#### Directory Structure Anti-Patterns

- **Monolithic dependencies**: Services depending on entire layers instead of specific components
- **Deep nesting**: Unnecessary directory depth (infrastructure/platform/security/vault/config)
- **Mixed concerns**: Application code mixed with infrastructure definitions

#### Deployment Ordering Issues

- **CRD usage before installation**: Custom resources before CRD controllers deployed
- **Layer violations**: Platform resources before infrastructure controllers
- **Missing health checks**: Critical dependencies without readiness verification

#### Security and Configuration Issues

- **Hardcoded secrets**: Secrets embedded in YAML instead of using external-secrets
- **Missing RBAC**: Services without proper service account permissions
- **Excessive permissions**: ClusterAdmin where namespace-scoped would suffice
- **Missing resource limits**: Deployments without CPU/memory constraints

### 4. Component-Specific Checks

#### HelmRelease Validation

- **Missing values files**: HelmRelease referencing non-existent values
- **Chart version inconsistencies**: Different components using different versions of same chart
- **Repository mismatches**: Charts referencing wrong or missing HelmRepository

#### Flux Kustomization Validation

- **Path validation**: Flux Kustomizations with incorrect path references
- **Source validation**: GitRepository sources that don't exist
- **Timeout inconsistencies**: Very short or very long timeouts without justification

#### External Dependencies

- **DNS dependencies**: Services requiring DNS without PowerDNS dependency
- **Certificate dependencies**: Ingress with TLS without cert-manager dependency
- **Storage dependencies**: PVCs without storage class configuration

### 5. Output Format

```markdown
# 🚨 CRITICAL: Broken References

## Missing kustomization resources
**Problem**: Resources listed in kustomization.yaml don't exist
- `path/kustomization.yaml:5` → `missing-file.yaml` (file not found)

**Fix**: Remove reference or create missing file

---

# 🔥 CRITICAL: Naming Inconsistencies

## Redundant directory prefixes
**Problem**: File names duplicate their directory names
- `authentik/authentik-config.yaml` → should be `authentik/config.yaml`
- `vault/vault-release.yaml` → should be `vault/helmrelease.yaml`

**Fix**: Rename files and update kustomization references

## Object type naming inconsistency
**Problem**: Mixed naming for same resource types
- `cert-manager/helmrelease.yaml` (HelmRelease)
- `authentik/release.yaml` (HelmRelease)

**Fix**: Standardize to `helmrelease.yaml` for all HelmRelease resources

---

# 🟡 DEPENDENCY ISSUES

## Missing Flux dependencies
**Problem**: Components use resources without declaring dependencies
- `applications/harbor/` uses ExternalSecret but missing `external-secrets` dependency
- `applications/gitea/` creates Ingress but missing `ingress-nginx` dependency

**Fix**: Add to flux-kustomization.yaml:
```yaml
dependsOn:
  - name: external-secrets
  - name: ingress-nginx
```

## Circular dependencies

**Problem**: Circular dependency chain detected

- `vault` → `authentik` → `vault` (via sso-secrets)

**Fix**: Use bootstrap secrets or staged deployment

---

## STRUCTURE VIOLATIONS

## Monolithic layer dependencies

**Problem**: Components depend on entire layers instead of specific services

- `applications/harbor/` depends on `platform` (contains 5 services)
- Only needs `vault` and `authentik`

**Fix**: Replace layer dependency with specific components

## Deep nesting anti-pattern

**Problem**: Unnecessary directory depth

- `infrastructure/platform/external-secrets/` → should be `external-secrets/`

**Fix**: Flatten directory structure

---

## CONFIGURATION ISSUES

## Missing health checks

**Problem**: Critical dependencies without readiness verification

- `authentik/flux-kustomization.yaml` missing healthCheck for CRD readiness

**Fix**: Add CRD health checks before resource creation

## Hardcoded secrets

**Problem**: Secrets embedded in YAML files

- `powerdns/secrets.yaml` contains base64 encoded values

**Fix**: Use external-secrets with vault backend

```yaml

### 6. Scan Categories

#### File Organization
- Naming consistency across components
- Directory structure best practices
- Missing or orphaned files
- Duplicate definitions

#### Reference Integrity
- Kustomization reference validation
- Flux dependency chain verification
- Resource reference validation
- Cross-component dependencies

#### GitOps Compliance
- Deployment ordering requirements
- Security best practices
- Resource management
- Configuration management

#### Component Health
- HelmRelease configuration
- Flux resource validation
- External dependency management
- Bootstrap readiness

### 7. Priority Classification

#### CRITICAL (Fix Immediately)
- Broken references that prevent deployment
- Missing files referenced in kustomizations
- Circular dependencies blocking bootstrap

#### HIGH (Fix Soon)
- Naming inconsistencies causing confusion
- Missing dependencies causing race conditions
- Security issues (hardcoded secrets, excessive permissions)

#### MEDIUM (Improve Over Time)
- Directory structure anti-patterns
- Monolithic dependencies
- Missing health checks

#### LOW (Nice to Have)
- Documentation inconsistencies
- Optimization opportunities
- Style consistency

### 8. Open-Ended Expert Analysis

#### Comprehensive Repository Review

**Agent Role**: Senior Kubernetes/GitOps consultant performing production readiness assessment

**Broad Analysis Areas:**
- **Architecture Patterns**: Evaluate overall design decisions and structural choices
- **Operational Excellence**: Assess monitoring, logging, alerting, and troubleshooting capabilities
- **Security Posture**: Review access controls, secrets management, network security
- **Scalability Design**: Analyze resource allocation, auto-scaling, performance patterns
- **Reliability Engineering**: Examine fault tolerance, recovery procedures, backup strategies
- **Developer Experience**: Evaluate ease of development, deployment, and debugging
- **Cost Optimization**: Identify resource waste, over-provisioning, optimization opportunities
- **Compliance Alignment**: Check against regulatory requirements, organizational policies

**Deep Inspection Methods:**
- **Resource Graph Analysis**: Map all resource relationships and data flows
- **Configuration Drift Detection**: Identify inconsistencies across similar components
- **Anti-Pattern Recognition**: Spot common Kubernetes/GitOps mistakes and code smells
- **Production Risk Assessment**: Evaluate what could fail in production environments
- **Maintenance Complexity**: Analyze operational burden and technical debt accumulation

**Expert Questions to Answer:**
- What would break first under load?
- Where are the single points of failure?
- How difficult would disaster recovery be?
- What security vulnerabilities exist?
- Where is configuration drift most likely?
- What would confuse a new team member?
- Which components are over-engineered or under-engineered?
- What operational toil could be eliminated?

## Implementation Notes

### Scan Methods

**Primary**: Comprehensive expert analysis using deep Kubernetes/GitOps domain knowledge
**Secondary**: Systematic validation using these specific methods:

1. **File System Analysis**: Find all YAML files, check naming patterns
2. **Reference Validation**: Parse kustomizations, verify file existence
3. **Dependency Graph**: Build component dependency map, detect circles
4. **Resource Analysis**: Parse YAML content, check resource references
5. **Best Practice Rules**: Apply GitOps patterns, security guidelines
6. **Expert Pattern Recognition**: Identify subtle issues requiring domain expertise
7. **Operational Readiness Assessment**: Evaluate production deployment viability
8. **Architecture Review**: Assess overall design quality and maintainability

### Detection Patterns

- **Expert heuristics**: Apply senior-level Kubernetes knowledge to spot complex issues
- **Pattern recognition**: Identify anti-patterns and architectural smells
- **Operational analysis**: Evaluate real-world deployment and maintenance scenarios
- **Security assessment**: Review access patterns and vulnerability exposure
- **Performance evaluation**: Analyze resource usage and scaling characteristics
- **Compliance validation**: Check against industry standards and best practices

**Plus specific technical validation:**
- **Regex patterns**: `component-*.yaml` in `component/` directory
- **File existence**: All kustomization resources must exist
- **YAML parsing**: Extract resource references, validate targets
- **Graph traversal**: Detect circular dependencies in Flux dependsOn chains

This command provides both systematic validation and expert-level analysis to maintain repository
quality, operational readiness, and long-term maintainability of GitOps infrastructure.
