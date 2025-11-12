# Home Proxmox → Talos Cluster Plan

This document tracks project roadmap and strategic architecture decisions for the Talos cluster implementation.


## SSO Platform Services - To Do

### 📋 Platform Services (Not yet implemented)
- [ ] **Vault**: Deploy secret management with Kubernetes auth, standalone mode with TLS
- [ ] **External Secrets Operator**: Enable Vault → K8s secrets bridge 
- [ ] **Authentik**: Deploy identity provider with blueprint-based configuration
- [ ] **Authentik & Vault GitOps Implementation**: Set up Authentik and Vault via GitOps and document their bootstrap process (beyond just GitOps/Tofu configuration)
- [ ] **Gitea**: Git service with Authentik OIDC integration
- [ ] **Harbor**: Container registry with Authentik OIDC authentication  
- [ ] **Matrix/Synapse**: Chat platform with Authentik SSO integration
- [ ] **Cross-integration**: Vault OIDC auth + Authentik-Vault secrets management

### Other Infrastructure Tasks
- [ ] **PowerDNS Zone Automation**: Implement proper zone management in Ansible  
- [ ] **Backup/recovery**: Document cluster restore procedures and etcd backup automation
- [ ] **VPS proxy resilience**: Investigate if VPS proxy to just *one* worker's ingress, or is it resilient to losing a worker? (HA)
- [ ] **VIP bootstrap handling**: Document how we solved VIP chicken-and-egg problem (couldn't bootstrap with cluster_endpoint=VIP since VIP doesn't exist until after bootstrap completes)

## SSO Architecture Design

We can use existing ducktape k3s cluster for reference.
The goal is to test and refine SSO integration before potentially switching from ducktape cluster to this cluster.

### Reference Implementation Analysis

**Existing ducktape k3s cluster** (`~/code/ducktape/k8s/helm/`) provides battle-tested patterns:

**Core SSO Components:**
- **Authentik**: Central identity provider with blueprint-based declarative configuration
- **Vault**: Secret storage with External Secrets Operator integration (Kubernetes auth)  
- **External Secrets**: Vault → K8s secrets bridge, eliminating direct service Vault integration
- **Reflector**: Cross-namespace secret sharing for OAuth client credentials

**User Management Patterns:**
- **Declarative users**: Git-managed blueprints defining users and group memberships
- **Group-based access**: `gitea-users`, `gitea-admins`, `rspcache-admins` groups
- **Auto-provisioning**: OIDC claims automatically create users in downstream services

**Secret Distribution Architecture:**
```
Vault KV Store → External Secrets Operator → K8s Secrets → Application Pods
```

**Service Integration Examples:**
- **Gitea**: OIDC with auto-registration, group-based permissions, shared OAuth secrets
- **Matrix/Synapse**: OIDC integration with signing certificates via Vault
- **Harbor**: OIDC provider integration (referenced in terraform config)

### Migration Strategy for Testing Cluster

**Critical Dependency Management:**
The architecture has a circular dependency: **Vault needs Authentik** (OIDC auth) ↔ **Authentik needs Vault** (client secret storage). Solution: **Temporal separation** with phased deployment.

**Phase 1: Core Infrastructure (Bootstrap)**
1. **Vault Deployment**: Port `helm/vault/` configuration to Flux GitOps
   - TLS-enabled standalone mode with persistent storage
   - **No OIDC initially** - root token auth only
   - ClusterSecretStore for External Secrets integration  
   - Kubernetes authentication for service account access

2. **External Secrets Operator**: Enable Vault → K8s secrets flow
   - ClusterSecretStore pointing to Vault instance
   - ServiceAccount-based authentication via Kubernetes auth

**Phase 2: Identity Provider (Minimal)**
1. **Authentik Setup**: Port blueprint-based configuration **without Vault integration**
   - PostgreSQL + Redis dependencies
   - Blueprint system for users/groups/basic providers only
   - **Exclude** `authentik-blueprints-vault` initially
   - Ingress at `auth.test-cluster.agentydragon.com`

2. **Basic User Management**: Essential blueprints only
   ```yaml
   # Phase 2: Only non-Vault blueprints
   blueprints:
     configMaps:
       - authentik-blueprints-users
       - authentik-blueprints-gitea  
       - authentik-blueprints-harbor
       # - authentik-blueprints-vault  # Added in Phase 4
   ```

**Phase 3: Cross-Integration**
1. **Vault OIDC Configuration**: Post-install job enables human access
   - Vault `auth/oidc/config` pointing to Authentik
   - Creates `authentik-users` role with appropriate policies
   - Now humans can login to Vault via Authentik SSO

2. **Authentik-Vault Integration**: Helm upgrade adds Vault blueprint
   - Add `authentik-blueprints-vault` ConfigMap
   - Vault client credentials via External Secrets
   - Authentik can now manage Vault access for users

**Phase 4: Platform Services with SSO**
1. **Gitea**: Git repository hosting with OIDC integration
   - Auto-registration from Authentik OIDC claims
   - Group-based permissions (admins vs users)
   - Shared OAuth secrets via External Secrets

2. **Harbor**: Container registry with OIDC authentication
   - Project-level access control via groups
   - Integration with cluster image pull workflows

3. **Matrix**: Chat/collaboration with OIDC SSO
   - Auto-user provisioning from identity provider
   - Certificate management via Vault integration

### Domain Strategy
- **Identity**: `auth.test-cluster.agentydragon.com` 
- **Git**: `git.test-cluster.agentydragon.com`
- **Registry**: `registry.test-cluster.agentydragon.com`
- **Chat**: `chat.test-cluster.agentydragon.com`

### Key Implementation Advantages
- **Battle-tested patterns**: Leveraging proven ducktape architecture
- **Service simplicity**: Applications use standard K8s secrets, not direct Vault integration  
- **Declarative management**: Git-driven user and permission management
- **OAuth automation**: Shared secrets and client registration via blueprints
- **External Secrets pattern**: Clean separation between secret storage and consumption

### Success Metrics
- Single sign-on across all platform services
- Auto-provisioning of users in Gitea, Harbor, Matrix from central identity
- Git-managed user and permission definitions
- Zero direct Vault integration in application services
- Seamless secret rotation via External Secrets Operator

This design provides a modernized platform experience while maintaining operational simplicity through proven patterns from the existing ducktape cluster.

## GitOps Representation: Multi-Stage Dependencies

### Flux Kustomization Dependency Management

**Challenge:** Complex dependencies between core infrastructure components require careful orchestration while maintaining GitOps principles.

**Solution:** Flux `dependsOn` with phased Kustomizations for automated, ordered deployment.

### Repository Structure
```
apps/
├── kustomizations/
│   ├── phase1-infrastructure.yaml    # Vault + External Secrets
│   ├── phase2-identity.yaml          # Authentik (minimal)  
│   ├── phase3-integration.yaml       # Cross-integration
│   └── phase4-services.yaml          # Platform services
├── phase1/
│   ├── vault/helmrelease.yaml        # Bootstrap config
│   └── external-secrets/helmrelease.yaml
├── phase2/  
│   └── authentik/helmrelease.yaml    # No Vault blueprint
├── phase3/
│   ├── vault/helmrelease.yaml        # Enable OIDC
│   └── authentik/helmrelease.yaml    # Add Vault blueprint
└── phase4/
    ├── gitea/helmrelease.yaml
    ├── harbor/helmrelease.yaml
    └── matrix/helmrelease.yaml
```

### Kustomization Dependencies
```yaml
# apps/kustomizations/phase1-infrastructure.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: phase1-infrastructure
  namespace: flux-system
spec:
  interval: 10m
  path: ./apps/phase1
  sourceRef:
    kind: GitRepository
    name: cluster
  # No dependencies - deploys first

---
# apps/kustomizations/phase2-identity.yaml  
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: phase2-identity
  namespace: flux-system
spec:
  interval: 10m
  path: ./apps/phase2
  sourceRef:
    kind: GitRepository
    name: cluster
  dependsOn:
    - name: phase1-infrastructure

---
# apps/kustomizations/phase3-integration.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1  
kind: Kustomization
metadata:
  name: phase3-integration
  namespace: flux-system
spec:
  interval: 10m
  path: ./apps/phase3
  sourceRef:
    kind: GitRepository
    name: cluster
  dependsOn:
    - name: phase2-identity

---
# apps/kustomizations/phase4-services.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization  
metadata:
  name: phase4-services
  namespace: flux-system
spec:
  interval: 10m
  path: ./apps/phase4
  sourceRef:
    kind: GitRepository
    name: cluster
  dependsOn:
    - name: phase3-integration
```

### Deployment Flow

**Fresh Cluster Recreation:**
```bash
# Single command deployment
git clone https://github.com/agentydragon/cluster.git
cd cluster  
flux bootstrap github --owner=agentydragon --repository=cluster

# Flux automatically executes:
# Phase 1: Vault + External Secrets → Ready
# Phase 2: Authentik minimal → Ready  
# Phase 3: Cross-integration → Ready
# Phase 4: Platform services → Complete
```

**Operational Benefits:**

1. **Dependency-Aware**: Flux respects `dependsOn` ordering automatically
2. **Failure Isolation**: Failed phases block dependents, not the entire stack
3. **Declarative Recreation**: `git clone` + `flux bootstrap` = full working stack  
4. **Selective Updates**: Change individual phases, Flux applies with correct dependencies
5. **Operational Visibility**: `flux get kustomizations` shows phase status

**Monitoring Deployment:**
```bash
# Check overall status
flux get kustomizations

# Watch specific phase
flux logs --follow --kind=Kustomization --name=phase2-identity

# Debug dependencies
kubectl get kustomizations -A -o wide
```

### Pattern Applications

This **multi-stage dependency pattern** applies to other complex deployments:

- **Observability Stack**: Base metrics → Prometheus → Grafana → Dashboards
- **CI/CD Pipeline**: Registry → Git → Builder → Deployer  
- **Data Platform**: Storage → Database → Processing → Analytics
- **ML Platform**: Jupyter → MLflow → Kubeflow → Serving

**Key Principle:** Break circular/complex dependencies into **temporal phases** with Flux `dependsOn` for automated, reproducible, GitOps-native orchestration.
