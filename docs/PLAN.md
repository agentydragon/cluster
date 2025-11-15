# Home Proxmox → Talos Cluster Plan

This document tracks project roadmap and strategic architecture decisions for the Talos cluster implementation.

## Done

### Core Infrastructure

- [x] **Talos Cluster**: 5-node HA cluster (3 controllers, 2 workers) with GitOps
- [x] **Networking**: Clean IP scheme (10.0.1.x controllers, 10.0.2.x workers, 10.0.3.x VIPs)
- [x] **CNI Architecture Decision**: Cilium managed by Terraform (infrastructure layer), not Flux (GitOps layer)
  - **Rationale**: Prevents circular dependency where GitOps tools manage their own networking infrastructure
  - **Why Flux Cannot Manage CNI**: When Flux tries to update Terraform-installed Cilium, worker nodes become permanently
    NotReady. During CNI transition gaps, nodes cannot pull container images (no networking), creating deadlock where
    nodes need networking to restore networking.
  - **Industry Pattern**: AWS EKS Blueprints, GKE Autopilot manage CNI at infrastructure layer
  - **Architecture Separation**: Talos→CoreDNS, Terraform→CNI, Flux→Applications
- [x] **GitOps**: Flux CD managing application platform with proper dependency ordering
- [x] **VIP HA**: Cluster API on 10.0.3.1 with bootstrap chicken-and-egg solution
- [x] **Secrets**: sealed-secrets with keyring-based keypair persistence for turnkey GitOps
- [x] **Turnkey Deployment**: Complete destroy→recreate→verify cycle successful
  - **Primary Directive Achieved**: `terraform apply` → everything works declaratively
  - **No Manual Intervention Required**: Full automation from VM creation to working cluster
  - **Robust Credential Management**: SSH-based ephemeral tokens with automatic cleanup

### Storage Infrastructure - COMPLETE

- [x] **Proxmox CSI**: Native ZFS storage integration with proper credential management
  - **SSH-based Token Generation**: Ephemeral credential creation via SSH for security
  - **Declarative Cleanup**: Complete user/token lifecycle management with destroy provisioners
  - **Proper ACL Permissions**: Full Proxmox permissions (Datastore.*, SDN.Use, VM.*)
  - **JSON Boolean Handling**: Correct data type preservation for CSI configuration
  - **Talos Integration**: Node topology labels and container runtime compatibility
- [x] **Vault with Raft Storage**: Deployed using Proxmox CSI for persistent storage
  - **3-node HA Cluster**: Full Raft consensus with automatic leader election
  - **Bank-Vaults Operator**: Automatic initialization, unsealing, and configuration
  - **Pod-specific Addressing**: Each pod gets its own service (instance-0, instance-1, instance-2)
  - **Persistent Storage**: 10Gi Proxmox CSI volumes per pod for Raft data
  - **Turnkey Deployment**: Complete destroy→recreate→verify cycle successful
  - **GitOps Integration**: Managed via Flux with proper dependency ordering

### LoadBalancer & Networking - COMPLETE

- [x] **MetalLB**: L2 advertisement with dedicated VIP pools:
  - ingress-pool: 10.0.3.2 (NGINX Ingress)
  - dns-pool: 10.0.3.3 (PowerDNS)
  - services-pool: 10.0.3.4-20 (Harbor, Gitea, etc.)
- [x] **NGINX Ingress**: HA deployment using MetalLB LoadBalancer
- [x] **External Connectivity**: VPS proxy via Tailscale to cluster ingress

### DNS & Certificates - COMPLETE

- [x] **DNS Delegation**: Route 53 → VPS PowerDNS → Cluster PowerDNS (10.0.3.3)
- [x] **PowerDNS**: In-cluster authoritative DNS server with LoadBalancer service
- [x] **cert-manager**: Automatic SSL certificates via PowerDNS DNS-01 challenges
- [ ] PARTIAL **SNI Passthrough**: Port 8443 SNI from VPS to cluster (enables end-to-end SSL)
- [x] **VPS PowerDNS Zone Automation**: DNS delegation VPS→cluster (10.0.3.3)

## TODO

### 📋 Platform Services (Storage foundation complete, services ready for deployment)

- [x] **Vault**: Secret management with Raft storage deployed via GitOps - FULLY OPERATIONAL
  - **Status**: 3-node HA cluster successfully deployed with proper Raft consensus
  - **Fixed**: cluster_addr now uses pod-specific service names (instance-0, instance-1, instance-2)
  - **Working**: Full HA with 1 leader + 2 standby replicas, automatic failover, data replication
  - **Storage**: Proxmox CSI volumes with 10Gi per pod for Raft data persistence
  - **Auth**: Kubernetes authentication method configured by Bank-Vaults
  - **Ready for**: HTTPS configuration via cert-manager, production workloads
- [ ] **External Secrets Operator**: Enable Vault → K8s secrets bridge
- [ ] **PowerDNS Secret Migration**: Migrate PowerDNS API key from terraform-generated Kubernetes secrets to Vault
  - **Current State**: Using terraform-controller with cross-namespace secret copying (temporary workaround)
  - **Target State**: PowerDNS API key stored in Vault, synced to Kubernetes via ExternalSecrets operator
  - **Benefits**: Centralized secret management, proper rotation support, eliminates cross-namespace complexity
- [ ] **Authentik**: Deploy identity provider with blueprint-based configuration
- [ ] **Authentik & Vault GitOps**: Set up via GitOps and document bootstrap process
- [ ] **Gitea**: Git service with Authentik OIDC integration
- [ ] **Harbor**: Container registry with Authentik OIDC authentication
- [ ] **Matrix/Synapse**: Chat platform with Authentik SSO integration
- [ ] **Cross-integration**: Vault OIDC auth + Authentik-Vault secrets management

### 🔒 HTTPS & Certificate Automation

- [ ] **Vault HTTPS Configuration**: Enable TLS for Vault with cert-manager integration
  - **External URL**: `vault.test-cluster.agentydragon.com`
  - **Implementation**: Certificate resource + TLS listener configuration
  - **Benefits**: Secure API access, proper certificate trust chain
- [ ] **Universal HTTPS Auto-Transformer**: Create Kustomization transformer for automatic HTTPS enablement
  - **Goal**: Add HTTPS to any service with just 1 line (transformer reference)
  - **Features**: Auto-generate `{service}.test-cluster.agentydragon.com` DNS names, Certificate resources, volume mounts
  - **Pattern**: `transformers: [../../transformers/auto-https.yaml]` in any service kustomization
  - **Alternative**: Istio/Gateway API with automatic TLS termination at gateway level

### 🔧 Advanced System Extensions & Features

- [ ] **ZFS Extension**: Add ZFS filesystem support for advanced storage features (snapshots, checksums, compression)
- [ ] **NFS Utils Extension**: Enable NFS client/server support for easy file sharing across systems
- [ ] **gVisor Extension**: Add sandboxed container runtime for enhanced security when running untrusted workloads
- [ ] **Dedicated Longhorn Storage**: Evaluate adding separate disks (e.g., /dev/sdb) for 100% Longhorn usage vs
  current filesystem approach
- [ ] **Longhorn V2 Data Engine Feature Flag**: V2 data engine disabled by default due to 100% CPU core overhead per worker.
  Can be enabled via `longhorn_v2_enabled = true` terraform variable if ultra-high performance storage is needed.
  Alternative: Use Proxmox CSI for better resource efficiency with ZFS backend integration.

### 🤖 AI/ML Platform Services

- [ ] **Firecrawl**: Web scraping and content extraction service for AI agents

### Storage & Infrastructure Tasks - COMPLETED MIGRATION

## ✅ Proxmox CSI Successfully Implemented

**Migration from Longhorn to Proxmox CSI completed** due to resource efficiency:

**Longhorn V2 Analysis:**

- ❌ **High CPU Overhead**: V2 Data Engine with SPDK requires dedicated CPU cores at 100% utilization per worker
- ❌ **Resource Inefficient**: 2 workers × 4 cores each = 8 cores at 100% just for storage
- ❌ **Complexity**: Additional SPDK configuration and resource management overhead

**Proxmox CSI Advantages:**

- ✅ **Direct ZFS Integration**: Native Atlas ZFS storage with snapshots, checksums, compression
- ✅ **Resource Efficient**: No CPU overhead on worker nodes
- ✅ **Simplified Architecture**: Direct Proxmox API integration
- ✅ **Proven Reliability**: Uses existing ZFS infrastructure

## 🚨 OpenEBS LocalPV Talos Incompatibility (Archived Discovery)

Through systematic diagnosis of Bank-Vaults storage failures, discovered critical incompatibility:

**Root Cause Analysis:**

- ✅ OpenEBS LocalPV provisioner correctly creates PV objects and directories on host filesystem (`/var/lib/openebs/local/pvc-*`)
- ✅ Helper pods (`init-pvc-*`) run successfully and create directories with proper permissions
- ❌ **Kubelet cannot access OpenEBS directories** - kubelet runs in container with limited mounts
- ❌ In Talos kubelet.go:159, only `/var/lib/kubelet` is mounted, NOT `/var/lib/openebs`
- Result: PVC shows "Bound" but pods fail with "path does not exist" errors

**Diagnostic Process Used:**

1. Created minimal test PVC → tight feedback loop (PVC status → helper pod → directory creation → mount failure)
2. Deployed privileged debug pod → verified directories exist on host filesystem
3. Examined Talos kubelet source → confirmed kubelet container mount restrictions
4. **Conclusion**: OpenEBS creates directories kubelet cannot see due to Talos containerized kubelet design

**Solutions Required:**

- [ ] **Add OpenEBS mount to Talos machine config**: Modify kubelet extraMounts to include `/var/lib/openebs`
- [ ] **Alternative**: Switch to Longhorn or Proxmox CSI with proper Talos integration
- [ ] **Temporary**: Use hostPath volumes directly (not production-suitable)

**Lessons:**

- Talos kubelet containerization requires explicit mount configuration for storage providers
- Always test storage with actual pod mounting, not just PV provisioning
- Tight diagnostic feedback loops (test PVC → debug pod → source analysis) are essential

### Other Storage & Infrastructure Tasks

- [ ] PARTIAL **Stream-level SNI Implementation**: SNI passthrough configured on port 8443, cluster handles SSL certificates
- [ ] **VPS proxy resilience**: Test ingress HA - VPS nginx → MetalLB VIP pod failure handling
- [x] **Storage Evaluation COMPLETE**: Proxmox CSI selected and implemented
  - **Selected**: Proxmox CSI for native ZFS integration and resource efficiency
  - **Rejected**: Longhorn V2 (CPU overhead), OpenEBS (Talos incompatibility)
  - **Future**: Rook-Ceph available if distributed storage needed
- [ ] **Complete SNI Migration**: Move remaining VPS services to stream-level SNI passthrough
- [ ] **Proxmox CSI Orphaned Volume Cleanup**: Add post-destroy cleanup for accumulated CSI volumes
  - **Issue**: With `reclaimPolicy: "Retain"`, destroyed clusters leave behind vm-*-disk-[2-9] volumes in Proxmox
  - **Solution**: Add terraform destroy provisioner to clean orphaned CSI volumes:
    `pvesm list local-zfs | grep "vm-.*-disk-[2-9]" | xargs pvesm free`
  - **Benefit**: Prevents storage accumulation across multiple destroy→apply cycles
- [x] **Generate sealed-secrets keypair in terraform**: Fix turnkey bootstrap sealed secrets issue - IMPLEMENTED
  - **Problem Solved**: First bootstrap had no existing keypair to extract, stored "null" in keyring, destroy→apply failed
  - **Solution Implemented**: TLS keypair generated directly in terraform (sealed-secrets-keypair.tf)
  - **Result**: Deterministic keypair that persists across destroy→apply cycles
  - **Benefit**: Eliminates race conditions, ensures turnkey destroy→apply always works

### 🔍 Development & Quality Assurance

- [x] **Basic Dry-Run Validation**: Pre-commit hooks for `kustomize build --dry-run` and `helm template --dry-run`
  - **Catches**: Invalid YAML, missing references, template errors before they reach the cluster
  - **Would Have Caught**: flux-system/k8s-kustomization.yaml referencing non-existent `./k8s/infrastructure/networking`
- [ ] **Advanced Multi-Tool Resource Ownership Conflict Detector**: Build static analysis tool to detect when
  multiple systems (Terraform, Flux, Helm) try to manage the same Kubernetes resources
  - **Problem**: Silent resource conflicts causing runtime failures, architectural boundary violations
  - **Solution**: Parse Terraform plans, Flux kustomizations, Helm releases to build resource ownership map and detect conflicts
  - **Integration**: Extend existing dry-run hooks with resource extraction and conflict detection
  - **Existing Tools Gap**: Checkov, KICS, Terrascan focus on security/best practices, not multi-tool ownership conflicts

### Low-priority freezer

- [ ] **Backup/recovery**: Document cluster restore procedures and etcd backup automation
- [ ] **Conditional Tailscale Auth Key**: Only provision keys for new nodes (avoid regeneration)
- [ ] **Webhook Inbox**: Deploy webhook inbox service (ducktape term) for receiving webhooks from external services

## SSO Architecture Design

We can use existing ducktape k3s cluster for reference.
The goal is to test and refine SSO integration before potentially switching from ducktape cluster to this cluster.

### Legacy Ducktape cluster analysis

Existing ducktape k3s cluster (`~/code/ducktape/k8s/helm/`) contains:

#### Core SSO Components

- **Authentik**: Central identity provider with blueprint-based declarative configuration
- **Vault**: Secret storage with External Secrets Operator integration (Kubernetes auth)
- **External Secrets**: Vault → K8s secrets bridge, eliminating direct service Vault integration
- **Reflector**: Cross-namespace secret sharing for OAuth client credentials

#### User Management Patterns

- **Declarative users**: Git-managed blueprints defining users and group memberships
- **Group-based access**: `gitea-users`, `gitea-admins`, `rspcache-admins` groups
- **Auto-provisioning**: OIDC claims automatically create users in downstream services

#### Secret Distribution Architecture

Vault KV Store → External Secrets Operator → K8s Secrets → Application Pods

#### Service Integration Examples

- **Gitea**: OIDC with auto-registration, group-based permissions, shared OAuth secrets
- **Matrix/Synapse**: OIDC integration with signing certificates via Vault
- **Harbor**: OIDC provider integration (referenced in terraform config)

### Migration Strategy for Testing Cluster

**Critical Dependency Management:**
Circular dependency: **Vault needs Authentik** (OIDC auth) ↔ **Authentik needs Vault** (client secrets).
Solution: **Temporal separation** with phased deployment.

#### Phase 1: Core Infrastructure (Bootstrap)

1. **Vault Deployment**: Port `helm/vault/` configuration to Flux GitOps
   - TLS-enabled standalone mode with persistent storage
   - **No OIDC initially** - root token auth only
   - ClusterSecretStore for External Secrets integration
   - Kubernetes authentication for service account access

2. **External Secrets Operator**: Enable Vault → K8s secrets flow
   - ClusterSecretStore pointing to Vault instance
   - ServiceAccount-based authentication via Kubernetes auth

#### Phase 2: Identity Provider (Minimal)

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

#### Phase 3: Cross-Integration

1. **Vault OIDC Configuration**: Post-install job enables human access
   - Vault `auth/oidc/config` pointing to Authentik
   - Creates `authentik-users` role with appropriate policies
   - Now humans can login to Vault via Authentik SSO

2. **Authentik-Vault Integration**: Helm upgrade adds Vault blueprint
   - Add `authentik-blueprints-vault` ConfigMap
   - Vault client credentials via External Secrets
   - Authentik can now manage Vault access for users

#### Phase 4: Platform Services with SSO

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

This design modernizes the platform while maintaining simplicity through proven ducktape patterns.

## GitOps Representation: Multi-Stage Dependencies

### Flux Kustomization Dependency Management

**Challenge:** Complex dependencies between core infrastructure components require careful orchestration with GitOps principles.

**Solution:** Flux `dependsOn` with phased Kustomizations for automated, ordered deployment.

Break circular/complex dependencies into **temporal phases** with Flux `dependsOn`.
Flux respects `dependsOn` ordering automatically. Failed phases block dependents, not the entire stack.
