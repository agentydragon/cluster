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
- [x] **Secrets Management**: Hybrid approach with proper separation of concerns
  - **Infrastructure Secrets**: SealedSecrets for bootstrap (Proxmox CSI, Flux deploy key)
  - **Application Secrets**: External Secrets Operator (ESO) for runtime secrets from Vault
  - **Stable Keypair Strategy**: Pre-generated keypair stored in libsecret prevents SealedSecret decryption failures
  - **No Circular Dependencies**: Vault Stage 1 enables ESO before requiring SSO
- [x] **Turnkey Deployment**: Complete destroy→recreate→verify cycle successful via consolidated terraform
  - **Primary Directive Achieved**: `./bootstrap.sh` → everything works declaratively
  - **No Manual Intervention Required**: Single terraform apply with proper module dependencies
  - **Proper Module Structure**: PVE-AUTH → INFRASTRUCTURE → STORAGE + GITOPS + DNS
  - **Infrastructure Layout**: Layered terraform in numbered directories (00-persistent-auth, 01-infrastructure,
    02-services, 03-configuration)
  - **Cleanup**: Removed zombie `terraform/infrastructure/` directory (post-refactor remnant with empty state)

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

- [x] **DNS Delegation**: Route 53 delegates `test-cluster.agentydragon.com` to VPS PowerDNS (`ns1.agentydragon.com`)
- [x] **PowerDNS Deployment**: In-cluster authoritative DNS server with LoadBalancer service (10.0.3.3)
  - **Status**: FULLY OPERATIONAL ✅
  - **Backend**: MariaDB (switched from SQLite for automatic schema initialization)
  - **Deployment**:
    - [x] Custom PowerDNS Helm chart (charts/powerdns/)
    - [x] Binary paths: `/usr/local/sbin/pdns_server` (official image location)
    - [x] Image: `powerdns/pdns-auth-49:4.9.11` (Docker Hub verified)
    - [x] Proxmox CSI storage integration for MariaDB data
    - [x] External Secrets Operator integration for API key
    - [x] Pod Security Standards "restricted" compliance
    - [x] AXFR configuration for VPS secondary zone replication
  - **AXFR Configuration**:
    - `allow-axfr-ips: "10.0.0.0/8,100.64.0.3"` (cluster network + VPS Tailscale IP)
    - `disable-axfr: "no"` (enable zone transfers)
  - **Previous Infrastructure Issue** (RESOLVED):
    - Containerd crash on worker0 left zombie kubelet process
    - PowerDNS pods stuck Pending - CSI mount operations blocked
    - Fixed via cluster rebuild
- [x] **external-dns**: Automatic DNS record creation for ingresses
  - **Status**: DEPLOYED AND WORKING ✅
  - **Provider**: PowerDNS native provider (HTTP API)
  - **Functionality**: Automatically creates A records and TXT metadata for ingresses
- [x] **cert-manager webhook**: Automatic SSL certificates via PowerDNS DNS-01 challenges
  - **Status**: DEPLOYED ✅
  - **Webhook**: cert-manager-webhook-powerdns for DNS-01 validation
  - **Configuration**: ClusterIssuer `letsencrypt-prod-dns` using PowerDNS webhook
- [x] **DNS Architecture - AXFR Secondary Zone**:
  - **Decision**: VPS PowerDNS acts as secondary nameserver for `test-cluster.agentydragon.com`
  - **Primary**: Cluster PowerDNS (10.0.3.3) - authoritative source of truth
  - **Secondary**: VPS PowerDNS - public-facing nameserver with AXFR replication
  - **Rationale**: VPS runs PowerDNS authoritative server (not recursor), requires AXFR not forwarding
  - **Zone Transfer**: Automatic AXFR from cluster to VPS over Tailscale VPN
  - **Public Resolution**: Let's Encrypt and external clients query VPS (Route 53 delegation)
  - **Connectivity**: Tailscale mesh with route advertisement (10.0.3.0/27)
- [x] **Tailscale Route Advertisement**: VPS→Cluster connectivity for DNS AXFR
  - **Routes Advertised**: `10.0.3.0/27` (covers all VIPs: API, Ingress, DNS, Services pool)
  - **Configuration**: Control plane nodes advertise routes via Tailscale extension
  - **Tags**: `tag:cluster-router` for route advertisement
  - **Fix Applied**: Corrected invalid CIDR `10.0.3.4/28` → `10.0.3.0/27` (was causing Tailscale crash)
  - **Status**: Routes enabled in Headscale, VPS can reach cluster DNS at 10.0.3.3 ✅
- [x] **VPS PowerDNS Secondary Configuration**:
  - **File**: `~/code/ducktape/ansible/roles/powerdns/templates/pdns.conf.j2`
  - **Change**: Added `secondary=yes` to enable automatic zone transfers
  - **Deployment**: Ansible role `powerdns` with tag `--tags powerdns`
  - **Verification**: `pdnsutil list-zone test-cluster.agentydragon.com` shows all cluster records
  - **Status**: Zone replication working, public DNS queries resolved ✅
- [x] **PowerDNS Operator**: DEPLOYED AND WORKING ✅ - Created test-cluster.agentydragon.com zone
  (ClusterZone CRD successful). external-dns uses HTTP API for record management.
  - **Current**: external-dns + custom PowerDNS Helm chart
  - **Alternative**: PowerDNS Operator (34⭐, Aug 2024) for zone/record management only
  - **Limitation**: Operator doesn't deploy PowerDNS servers - only manages zones/records via API
  - **Evaluate**: Whether zone-only management offers advantages over external-dns direct integration
- [ ] **Technitium DNS Evaluation**: Alternative to PowerDNS for authoritative DNS
  - **Alternative**: Technitium DNS Server (4.6k⭐, active development, excellent API)
  - **Pros**: Modern architecture, comprehensive DNSSEC, excellent web UI, official Docker images
  - **Cons**: RFC2136-only integration (no native external-dns provider), TSIG key complexity, newer K8s ecosystem
  - **Integration**: Would require RFC2136 for both external-dns and cert-manager (vs PowerDNS native providers)
  - **Evaluate**: Whether advanced features justify integration complexity vs PowerDNS simplicity
- [x] **SNI Passthrough on Port 443**: IMPLEMENTED ✅ - Stream-level SNI routing on port 443 via
  nginx-streams/https-sni-router.j2 (L358 verified, `listen 443; ssl_preread on`)
  - **Current**: VPS nginx configured with TLS stream SNI router to cluster ingress VIP (10.0.3.2:443)
  - **Configuration**: `nginx-streams/https-sni-router.j2` routes `*.test-cluster.agentydragon.com` to cluster
  - **Limitation**: Public endpoint on port 8443, not 443 (requires SNI setup on VPS nginx for port 443)
  - **Impact**: HTTP-01 ACME challenges fail (Let's Encrypt only supports ports 80/443, not 8443)
- [x] **Let's Encrypt Certificates**: Automatic TLS certificates via cert-manager - WORKING ✅
  - **Status**: DNS infrastructure and cert-manager fully operational
  - **DNS Configuration**: All A records point to VPS IP (172.235.48.86) ✅
  - **Authoritative DNS**: PowerDNS serving from `ns1.agentydragon.com` ✅
  - **Challenge Solvers**:
    - **DNS-01** (PowerDNS webhook): Works for wildcard domains (*.test-cluster.agentydragon.com) ✅
    - **HTTP-01** (nginx ingress): Configured but blocked by port 8443 limitation ⚠️
  - **Current Workaround**: Use DNS-01 solver (wildcard certs) until port 443 SNI is configured
  - **Services**: Gitea, Vault, Harbor, Authentik all accessible ✅

## TODO

### 📋 Platform Services

- [x] **Vault**: Secret management with Raft storage deployed via GitOps - FULLY OPERATIONAL
  - **Status**: 3-node HA cluster successfully deployed with proper Raft consensus
  - **Fixed**: cluster_addr now uses pod-specific service names (instance-0, instance-1, instance-2)
  - **Working**: Full HA with 1 leader + 2 standby replicas, automatic failover, data replication
  - **Storage**: Proxmox CSI volumes with 10Gi per pod for Raft data persistence
  - **Auth**: Kubernetes authentication method configured by Bank-Vaults
  - **Ready for**: HTTPS configuration via cert-manager, production workloads
- [x] **External Secrets Operator**: Vault → K8s secrets bridge deployed and configured
  - **Status**: ClusterSecretStore configured with Vault backend, operator+config phases separated
  - **Working**: ESO can generate passwords and sync secrets from Vault to Kubernetes
  - **Fixed**: Chicken-and-egg problem resolved via phased deployment (operator → config)
  - **Stabilization**: Changed refresh intervals to 8760h (1 year) to prevent auth desync (see below)
- [ ] **Secret Rotation Infrastructure**: Proper secret rotation without service disruption
  - **Problem**: ESO Password generators regenerate on refresh → applications desynchronize → auth failures
  - **Root Cause**: Apps persist secrets (DB init, Job writes) → ESO refresh changes secret →
    app still has old value
  - **Current Fix**: Extended refresh intervals to 8760h (stopgap)
  - **Proper Solution** (3 phases):
    1. **Deploy Stakater Reloader**: Auto-restart pods when secrets change (solves 90% of cases)
    2. **Fix Init-Time Patterns**: Architecture changes for apps that persist secrets
       - PowerDNS: Support multiple valid API keys or dynamic DB updates
       - Authentik: Overlapping token validity or CronJob pattern
       - PostgreSQL: Accept manual rotation or ALTER USER automation
    3. **Migrate to Vault KV**: Store generated passwords in Vault (persistent) vs ESO generators
       (ephemeral)
  - **Reference**: See `docs/SECRET_SYNCHRONIZATION_ANALYSIS.md` for full analysis
  - **Status**: Phase 0 complete (stabilization), Phases 1-3 TODO
- [x] **Authentik Bootstrap**: ESO password generator provides bootstrap token (no circular dependency)
  - **Architecture**: Vault Stage 1 (unsealed) enables ESO → ESO generates Authentik bootstrap token
  - **No Circular Dependency**: Vault doesn't require SSO initially, Authentik gets secrets from ESO
- [x] **Authentik**: Identity provider deployed with ESO-generated secrets - OPERATIONAL
  - **Status**: Successfully deployed with proper PostgreSQL and secret key configuration
  - **Working**: Admin interface accessible, ESO provides all secrets (admin password, secret key, postgres)
  - **Fixed**: envFrom pattern for secret injection, separated core deployment from SSO configuration
  - **Ready for**: Blueprint-based configuration and service integration
- [x] **PowerDNS Custom Chart Deployment**: DEPLOYED ✅ - Custom PowerDNS Helm chart operational with
  ESO integration, official images, modern security
  - **Status**: Custom chart created with ESO integration, official images, modern security
  - **Next Steps**:
    1. Create ESO secret for PowerDNS API key
    2. Deploy custom chart via GitRepository
    3. Verify PowerDNS API and LoadBalancer
  - **TODO**: Pin PowerDNS image to specific version instead of using 'latest' tag
- [ ] **PowerDNS API Key via ESO**: Generate PowerDNS API key using External Secrets Operator
  - **Current State**: Chart ready for ESO integration, need Vault secret + ExternalSecret
  - **Implementation**: `vault kv put kv/powerdns apikey="$(openssl rand -base64 32)"`
- [ ] **external-dns Deployment**: Deploy external-dns with PowerDNS provider once PowerDNS is working
  - **Status**: Configuration ready, needs PowerDNS API endpoint
- [ ] **cert-manager webhook Deployment**: Deploy PowerDNS webhook for DNS-01 challenges
  - **Status**: Configuration ready, needs PowerDNS API endpoint
- [ ] **Test Auto-Ingress Flow**: Verify ingress → DNS record → certificate automation works end-to-end
- [x] **Gitea**: Git service deployed with chart auto-managed PostgreSQL - OPERATIONAL
  - **Status**: Successfully deployed with ingress at git.test-cluster.agentydragon.com:8443
  - **Working**: Admin authentication via ESO-generated password, PostgreSQL auto-managed by chart
  - **TLS**: Let's Encrypt certificate configured (pending port 443 SNI setup for HTTP-01 validation)
  - **Fixed**: Chart version updated to 12.4.0, ingress enabled with nginx controller, TLS annotations added
  - **Ready for**: Authentik OIDC integration
- [ ] **Harbor**: Container registry with Authentik OIDC authentication
- [ ] **Matrix/Synapse**: Chat platform with Authentik SSO integration
- [ ] **InvenTree**: Open-source inventory management system
  - **Helm Chart**: Available from TrueCharts (v9.0.12)
  - **Chart Location**: <https://artifacthub.io/packages/helm/truecharts/inventree>
  - **Integration**: Will use Authentik OIDC for authentication
  - **Status**: Researched, ready for deployment
- [ ] **Syncthing**: Continuous file synchronization
  - **Helm Chart**: Community charts available (TrueCharts, k8s-home-lab-repo)
  - **Recommended Chart**: TrueCharts `oci://oci.trueforge.org/truecharts/syncthing`
  - **Note**: Port configuration challenge (Syncthing port 22000 vs K8s NodePort 32000+)
  - **Use Case**: File sync between cluster and external systems
  - **Status**: Researched, ready for deployment
- [ ] **Bazel Remote Cache**: Distributed build cache for Bazel builds
  - **Helm Chart**: Available from slamdev (v0.0.6)
  - **Chart Location**: <https://artifacthub.io/packages/helm/slamdev/bazel-remote>
  - **Alternative**: Official kubernetes.yml in buchgr/bazel-remote repo
  - **Images**: buchgr/bazel-remote-cache, quay.io/bazel-remote/bazel-remote
  - **Warning**: Don't name deployment "bazel-remote" (env var conflicts)
  - **Use Case**: Speed up Bazel builds across development team
  - **Status**: Researched, ready for deployment
- [ ] **ActivityWatch Server**: Open-source automated time tracker
  - **Helm Chart**: ❌ No official or community Helm chart available
  - **Docker Images**: ephillipe/activitywatch-server-docker (community)
  - **Implementation**: Requires custom Helm chart creation
  - **Challenge**: Designed for desktop/local use, not centralized server deployments
  - **Use Case**: Track development time and activity patterns
  - **Status**: Researched, requires custom chart work
- [ ] **Google Drive Sync/Backup**: Headless Google Drive client for cloud backup
  - **Implementation**: Custom deployment using existing binary (borrowed from Jupyter images)
  - **Binary Location**: Already available in user's infrastructure
  - **History**: Proven working implementation on personal computers
  - **Helm Chart**: Requires custom chart creation with existing binary
  - **Use Case**: Automated backup and sync of cluster data to Google Drive
  - **Authentication**: Will need service account or OAuth token management via Vault/ESO
  - **Status**: Binary available, ready for containerization and deployment
- [ ] **Vault SSO Integration**: Configure Vault with Authentik OIDC authentication
  - **Current State**: Vault deployed and operational with root token auth only
  - **Goal**: Enable human access to Vault via Authentik SSO
  - **Implementation**: Configure `auth/oidc/config` pointing to Authentik, create `authentik-users` role
  - **Benefit**: Centralized authentication, audit trail, group-based Vault policies
- [ ] **User Management Automation**: Automated user provisioning in Authentik
  - **Requirement**: Create <agentydragon@gmail.com> user with password
  - **Acceptable Solution**: One-time command/script for user creation (doesn't need to be fully automated)
  - **Integration**: Use Authentik bootstrap blueprints or direct API calls
  - **Status**: Needs implementation
- [ ] **Fix SSO Terraform Integration**: Resolve 403/503 errors in gitea-sso and matrix-sso terraform resources
  - **Current Issue**: Terraform runners getting HTTP 403 "Token invalid/expired" and 503 "Service Temporarily Unavailable"
  - **Root Cause**: API token or Authentik ingress issues (auth.test-cluster.agentydragon.com shows 503 at 00:21)
  - **Status**: Connectivity fixed (using HTTPS URL), authentication/availability issues remain
  - **Impact**: Blocks Gitea and Matrix SSO configuration
- [ ] **Firecrawl**: AI-powered web scraping and content extraction service
  - **Reference**: <https://github.com/firecrawl/firecrawl/tree/main/examples/kubernetes/cluster-install>
  - **Helm Chart**: <https://github.com/firecrawl/firecrawl/blob/main/examples/kubernetes/firecrawl-helm/README.md>
  - **Components**: Firecrawl service + MCP (Model Context Protocol) server integration
  - **Purpose**: Provide web scraping/extraction for AI agents (Claude, etc.)
  - **Use Case**: AI-powered research, documentation scraping, content analysis
  - **Status**: Researched, ready for deployment
- [ ] **Harbor as Cluster Registry**: Use Harbor for all cluster container images with fallback to public registries
  - **Goal**: Pull all images from internal Harbor registry for reliability and caching
  - **Challenge**: Bootstrap story - how to deploy Harbor before Harbor can serve its own images
  - **Solution Options**:
    - Bootstrap phase using public registries, then switch to Harbor
    - Harbor pulls from public → cluster pulls from Harbor (cache proxy)
    - Image mirroring automation (sync public images to Harbor)
  - **Benefit**: Faster deployments, offline capability, vulnerability scanning
  - **Status**: Needs architecture design
- [ ] **MCP Servers Deployment**: Run Model Context Protocol servers for AI agent integration
  - **Example**: GitHub MCP server instance for repository access
  - **Purpose**: Enable Claude Code and other AI tools to interact with services via MCP protocol
  - **Integration**: Connect to Firecrawl, GitHub, cluster APIs, documentation
  - **Use Case**: AI-assisted development, automated documentation, cluster management
  - **Status**: Needs deployment plan

- [ ] **Investigate PowerDNS Operator Restarts**: Operator has 33 restarts over 22h uptime
  - **Status**: Operator IS working (ClusterZone successfully created), but restart count suggests instability
  - **Goal**: Determine if restarts are normal, configuration issue, or resource constraint
  - **Impact**: Low priority - operator functional despite restarts
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
  - **Components**: Firecrawl service + MCP (Model Context Protocol) server integration
  - **Purpose**: Provide web scraping and content extraction capabilities for AI agents
  - **MCP Integration**: Enable Claude and other AI tools to crawl and extract web content
  - **Deployment**: Kubernetes deployment with MCP server for agent access
  - **Use Case**: AI-powered web research, documentation scraping, content analysis

### 📊 Observability & Monitoring

- [x] **metrics-server**: Kubernetes Metrics API provider - DEPLOYED AND WORKING ✅ (kubectl top nodes functional, 4h+ uptime)
  - **Purpose**: Enable `kubectl top nodes/pods`, Horizontal Pod Autoscaler (HPA), resource-based scheduling
  - **Status**: Currently missing - Metrics API returns "not available"
  - **Deployment**: Official kubernetes-sigs/metrics-server Helm chart
  - **Requirement**: Foundation for autoscaling and resource monitoring

- [x] **Prometheus Stack**: Complete metrics collection - FULLY DEPLOYED ✅
  (kube-prometheus-stack: Prometheus, Grafana, Alertmanager, node-exporter on all 6 nodes,
  kube-state-metrics. 4h+ uptime, all healthy)
  - **Recommended**: kube-prometheus-stack (all-in-one Helm chart)
  - **Components Included**:
    - **Prometheus**: Time-series metrics database with PromQL query language
    - **Grafana**: Visualization dashboards with pre-configured K8s dashboards
    - **Alertmanager**: Alert routing, grouping, and notification (Slack, email, PagerDuty)
    - **kube-state-metrics**: Kubernetes resource state metrics (pod status, deployments, etc.)
    - **node-exporter**: Node-level system metrics (CPU, memory, disk, network)
    - **Prometheus Operator**: CRD-based management (ServiceMonitor, PodMonitor, PrometheusRule)
  - **Chart**: prometheus-community/kube-prometheus-stack
  - **Storage**: Proxmox CSI for persistent metrics retention
  - **Alternatives**:
    - VictoriaMetrics (lighter, faster, better long-term storage)
    - Thanos (multi-cluster federation and long-term storage)

- [ ] **Loki Stack**: Log aggregation and analysis
  - **Components**:
    - **Loki**: Log aggregation backend (like Prometheus but for logs)
    - **Promtail**: DaemonSet log shipper (collects logs from all nodes)
    - **Grafana Integration**: Unified logs + metrics visualization
  - **Alternative**: Grafana Alloy (newer unified agent replacing Promtail)
  - **Chart**: grafana/loki-stack or grafana/loki-distributed (HA deployment)
  - **Storage**: Proxmox CSI for log retention
  - **Benefits**: LogQL query language, label-based indexing, cost-effective vs ELK stack

- [ ] **OpenTelemetry**: Distributed tracing and observability
  - **Purpose**: Trace requests across microservices, identify bottlenecks
  - **Components**:
    - **OpenTelemetry Operator**: Deploy and manage collectors
    - **OpenTelemetry Collector**: Receive, process, and export traces/metrics/logs
    - **Jaeger** or **Tempo**: Trace storage and visualization backends
  - **Integration**: Export to Prometheus (metrics) + Loki (logs) + Tempo (traces)
  - **Use Case**: Essential for complex service mesh debugging

- [ ] **Recommended Stack Priority**:
  1. **metrics-server** (immediate - fixes kubectl top)
  2. **kube-prometheus-stack** (core monitoring and alerting)
  3. **Loki + Promtail/Alloy** (log aggregation)
  4. **OpenTelemetry** (later - when microservices complexity warrants tracing)

- [ ] **Authentik Integration**: Configure Grafana OIDC with Authentik for SSO access to dashboards

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

- [x] **Stream-level SNI Implementation**: SNI passthrough configured on port 443, cluster handles SSL certificates
  - **Configuration**: nginx stream module with ssl_preread for SNI inspection
  - **Routing**: `*.test-cluster.agentydragon.com` → cluster ingress (10.0.3.2:443)
  - **Status**: VPS nginx properly configured with SNI passthrough
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
- [ ] **TFLint Rule Reconsideration**: Review disabled terraform linting rules and assess if they can be selectively re-enabled
  - **Current State**: Disabled terraform_required_version, terraform_required_providers, terraform_unused_required_providers
    to resolve conflict between terraform best practices (pin provider versions once in root) and tflint defaults
    (expect every module to have versions)
  - **Future Work**: Investigate per-directory tflint configs, upstream rule improvements, or custom rules that
    understand module inheritance patterns
  - **Context**: Current approach prioritizes "pin provider versions exactly once" architectural principle over
    linter compliance

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

### Current Service Status (2025-11-19)

**Operational:**

- ✅ git.test-cluster.agentydragon.com - Gitea (accessible)
- ✅ vault.test-cluster.agentydragon.com - Vault (operational, root token auth)
- ✅ registry.test-cluster.agentydragon.com - Harbor (deployed)

**Issues:**

- ⚠️ auth.test-cluster.agentydragon.com - Authentik (503 Service Unavailable at 00:21)
- ❌ chat.test-cluster.agentydragon.com - Matrix Synapse (404 Not Found)

**SSO Integration Status:**

- ✅ vault-config terraform: Working
- ✅ authentik-config terraform: Working
- ✅ sso-secrets terraform: Working
- ❌ gitea-sso terraform: Failing (403/503 errors)
- ❌ matrix-sso terraform: Failing (403/503 errors)

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
