# Harbor Registry Strategy

## Executive Summary

This document outlines a comprehensive strategy for using Harbor as the primary container
registry for the Talos cluster, with intelligent fallback to public registries. The strategy
addresses the bootstrap chicken-and-egg problem through a **pull-through cache proxy**
approach, enabling Harbor to transparently cache images from upstream registries while
serving as the primary image source for cluster workloads.

**Recommended Approach:** Deploy Harbor with **pull-through cache proxy** configuration,
using public registries during bootstrap, then gradually transition cluster workloads to pull
from Harbor. This provides immediate benefits (caching, bandwidth reduction) without
requiring pre-population or complex image mirroring automation.

**Key Benefits:**

- Faster pod startup times (cached images in-cluster)
- Reduced egress bandwidth and public registry rate limits
- Vulnerability scanning via Trivy integration
- Image provenance tracking and audit logs
- Improved offline capability and resilience

---

## 1. Bootstrap Problem Analysis

### The Chicken-and-Egg Challenge

**Problem Statement:** Harbor requires container images to run (PostgreSQL, Redis, Harbor
core services, registry backend), but if Harbor serves its own images, it cannot start without
already being available.

### Option A: Bootstrap Phase with Public Registries (REJECTED)

**Approach:** Deploy Harbor initially using public registries, then reconfigure all workloads
to use Harbor.

**Pros:**

- Simple initial deployment
- No circular dependency

**Cons:**

- Requires cluster-wide reconfiguration after Harbor deployment
- Complex cutover process with potential downtime
- All HelmReleases/deployments need image path updates
- GitOps churn (many commits to change image references)

**Verdict:** ❌ Too operationally complex for the benefit gained.

---

### Option B: Pull-Through Cache Proxy (RECOMMENDED)

**Approach:** Harbor acts as a transparent caching proxy for upstream registries. Workloads
pull from Harbor, Harbor pulls from upstream on cache miss.

**How It Works:**

1. Harbor deployed using public registries (initial bootstrap)
2. Create proxy cache projects in Harbor for each upstream registry:
   - `docker-hub-proxy` → `docker.io`
   - `ghcr-proxy` → `ghcr.io`
   - `quay-proxy` → `quay.io`
   - `registry-k8s-proxy` → `registry.k8s.io`
3. Configure cluster to pull from Harbor proxy projects
4. On first pull: Harbor fetches from upstream, caches locally, serves to client
5. Subsequent pulls: Harbor serves from cache (fast, local)

**Pros:**

- ✅ No chicken-and-egg: Harbor deploys normally from public registries
- ✅ Transparent caching: No pre-population required
- ✅ Immediate benefits: Caching starts on first pull
- ✅ Fallback built-in: Harbor proxies to upstream if cache miss
- ✅ Low operational complexity: Configure once, automatic thereafter
- ✅ Official Harbor feature: Well-supported and documented

**Cons:**

- First pull per image still reaches upstream (one-time cost)
- Requires Harbor availability for subsequent pulls (mitigated by cache hits)

**Verdict:** ✅ **RECOMMENDED** - Best balance of simplicity and functionality.

---

### Option C: Pre-Populate Critical Images (ALTERNATIVE)

**Approach:** Before deploying Harbor, manually push critical images into Harbor, then
configure cluster to use Harbor exclusively.

**Pros:**

- Complete control over image versions
- No upstream dependency after pre-population
- True air-gap capability

**Cons:**

- Labor-intensive: Identify all critical images, versions, architectures
- Brittle: Requires updating pre-population list as cluster evolves
- Complex automation: Image sync jobs, version tracking, multi-arch support
- Bootstrap complexity: External Harbor instance or VM required for initial push
- High maintenance burden

**Verdict:** ⚠️ Only for true air-gapped environments or compliance requirements.
Over-engineered for typical use cases.

---

## 2. Image Mirroring Strategy

### Which Images to Cache?

**Initial Phase:** All images pulled by cluster workloads automatically cached via
pull-through proxy.

**Critical Images** (high-priority for caching):

- **Core Infrastructure:** CNI (Cilium), CSI (Proxmox CSI), CoreDNS
- **GitOps:** Flux controllers, Kustomize controller, Helm controller
- **Platform Services:** Vault, Authentik, External Secrets Operator
- **Application Dependencies:** PostgreSQL, Redis, MariaDB charts
- **Monitoring:** Prometheus, Grafana, metrics-server

**Non-Critical Images** (lower priority):

- One-off jobs and debug pods
- Development/testing workloads

### Automation Approach

#### Phase 1: Passive Caching (Bootstrap)

- No automation required
- Harbor pull-through proxy automatically caches on first pull
- Zero manual intervention

#### Phase 2: Active Pre-Warming (Optional)

- Create Kubernetes CronJob to "warm" cache for critical images
- Job runs periodically: `docker pull <harbor-proxy>/<image>` for known critical images
- Ensures cache freshness before deployments

**Example CronJob:**

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: harbor-cache-warmer
  namespace: harbor
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: warmer
            image: docker:latest
            command:
            - /bin/sh
            - -c
            - |
              # Pull critical images to warm Harbor cache
              docker pull registry.test-cluster.agentydragon.com/docker-hub-proxy/library/postgres:16
              docker pull registry.test-cluster.agentydragon.com/ghcr-proxy/fluxcd/flux-cli:latest
              # Add more critical images...
          restartPolicy: OnFailure
```

#### Phase 3: Harbor Replication (Future)

- Harbor supports scheduled replication between registries
- Can pull images from upstream on schedule, not just on-demand
- Configuration: Harbor UI → Replications → New Replication Rule

### Handling Image Updates

**Pull-Through Cache Behavior:**

- Harbor respects upstream registry cache headers (TTL)
- Configurable cache expiration policies per project
- Manual refresh: Delete cached image in Harbor to force upstream re-pull

**Best Practice:**

- Use immutable tags (SHA digests) for production workloads
- Pin Helm chart versions (already done in cluster)
- Harbor's "Prevent vulnerable images from running" policy blocks known CVEs

### Storage Capacity Planning

**Current Allocation:**

- Registry storage: 5Gi (configured in HelmRelease)
- Trivy scanner storage: 5Gi

**Capacity Estimation:**

- Average image size: 100-500 MB
- Critical images: ~50 images × 300 MB = 15 GB
- Full cache (all workloads): 50-100 GB

**Scaling Strategy:**

- Start with 5Gi (sufficient for ~10-15 images)
- Monitor Harbor metrics: `harbor_registry_storage_bytes`
- Increase PVC size as needed: `kubectl edit pvc -n harbor`
- Proxmox CSI supports dynamic expansion

**Storage Management:**

- Enable Harbor garbage collection (cron job)
- Configure tag retention rules (keep last N versions)
- Alert on storage >80% full

---

## 3. Deployment Configuration

### Configuring Workloads to Use Harbor

#### Method 1: Image Path Rewrite (Recommended for New Deployments)

Update HelmRelease values or manifests to reference Harbor proxy:

```yaml
# Before:
image: docker.io/library/postgres:16

# After:
image: registry.test-cluster.agentydragon.com/docker-hub-proxy/library/postgres:16
```

#### Method 2: Containerd Registry Mirror (Transparent)

Configure Talos to automatically redirect image pulls to Harbor:

```yaml
# talos.tf machine configuration
machine:
  registries:
    mirrors:
      docker.io:
        endpoints:
          - https://registry.test-cluster.agentydragon.com/docker-hub-proxy
      ghcr.io:
        endpoints:
          - https://registry.test-cluster.agentydragon.com/ghcr-proxy
      quay.io:
        endpoints:
          - https://registry.test-cluster.agentydragon.com/quay-proxy
      registry.k8s.io:
        endpoints:
          - https://registry.test-cluster.agentydragon.com/registry-k8s-proxy
```

**Benefits of Method 2:**

- Completely transparent to workloads
- No manifest changes required
- Automatic for all pods cluster-wide
- Declarative infrastructure configuration

**Drawback:**

- Talos node reconfiguration triggers node reboot
- Needs testing to ensure Harbor availability before reconfiguration

**Verdict:** Use **Method 2** for long-term strategy, **Method 1** for initial testing.

### imagePullPolicy Settings

**Recommended Policy:**

```yaml
imagePullPolicy: IfNotPresent
```

**Rationale:**

- Reduces unnecessary pulls when image already on node
- Harbor cache hit rate improves over time
- Faster pod startup after first pull

**Alternative for Development:**

```yaml
imagePullPolicy: Always
```

- Ensures latest image version
- Useful when using `latest` tag (not recommended for production)

### Fallback Behavior if Harbor Unavailable

**Containerd Registry Mirror Fallback:**

Talos containerd configuration supports fallback:

```yaml
machine:
  registries:
    mirrors:
      docker.io:
        endpoints:
          - https://registry.test-cluster.agentydragon.com/docker-hub-proxy
          - https://registry-1.docker.io  # Fallback to upstream
```

**Behavior:**

1. Try Harbor first
2. If Harbor unreachable (connection refused, timeout), fall back to upstream
3. Containerd logs fallback events

**Caveats:**

- Fallback only works for **connection failures**, not Harbor authentication errors
- If Harbor returns 401/403, no fallback occurs (considered authoritative response)

**Production Best Practice:**

- Deploy Harbor with HA (multiple replicas)
- Monitor Harbor availability (Prometheus alerts)
- Consider Harbor across multiple failure domains if mission-critical

### Authentication and Image Pull Secrets

**Public Registry Proxy Projects:**

- No authentication required for pulling
- Harbor serves cached images without credentials

**Private Registry Proxy Projects:**

- Configure Harbor registry endpoint with upstream credentials
- Harbor authenticates to upstream, caches images
- Cluster workloads pull from Harbor without needing upstream credentials
- **Benefit:** Centralized credential management in Harbor

**Harbor-Hosted Images:**

- Create `imagePullSecret` for Harbor credentials
- ESO can generate secrets from Vault:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: harbor-pull-secret
  namespace: default
spec:
  secretStoreRef:
    name: cluster-secret-store
  target:
    template:
      type: kubernetes.io/dockerconfigjson
      data:
        .dockerconfigjson: |
          {
            "auths": {
              "registry.test-cluster.agentydragon.com": {
                "username": "{{ .username }}",
                "password": "{{ .password }}",
                "auth": "{{ (.username + ":" + .password) | b64enc }}"
              }
            }
          }
  data:
  - secretKey: username
    remoteRef:
      key: kv/harbor
      property: robot-username
  - secretKey: password
    remoteRef:
      key: kv/harbor
      property: robot-token
```

---

## 4. Rollout Plan

### Phase 1: Harbor Deployment (COMPLETE ✅)

**Status:** Harbor deployed and accessible at `registry.test-cluster.agentydragon.com`

**Components:**

- Harbor core services
- PostgreSQL database
- Redis cache
- Trivy vulnerability scanner
- Ingress with TLS certificates

**Verification:**

```bash
curl -k https://registry.test-cluster.agentydragon.com/api/v2.0/health
# Expected: {"status":"healthy"}
```

---

### Phase 2: Configure Pull-Through Cache Proxy

**Tasks:**

1. **Create Proxy Cache Registry Endpoints** (Harbor UI: Administration → Registries)
   - Docker Hub: `https://hub.docker.com`
   - GHCR: `https://ghcr.io`
   - Quay: `https://quay.io`
   - Kubernetes Registry: `https://registry.k8s.io`

2. **Create Proxy Cache Projects** (Harbor UI: Projects → New Project)
   - Name: `docker-hub-proxy`
     - Proxy Cache: Enabled
     - Registry: Docker Hub endpoint
     - Access Level: Public
   - Name: `ghcr-proxy`
     - Proxy Cache: Enabled
     - Registry: GHCR endpoint
     - Access Level: Public
   - Repeat for Quay, registry.k8s.io

3. **Verification:**

```bash
# Pull image through Harbor proxy
docker pull registry.test-cluster.agentydragon.com/docker-hub-proxy/library/nginx:alpine

# Verify cached in Harbor
curl -u admin:${HARBOR_PASSWORD} \
  https://registry.test-cluster.agentydragon.com/api/v2.0/projects/docker-hub-proxy/repositories
```

**Deliverable:** Functional pull-through cache for major upstream registries.

---

### Phase 3: Gradual Workload Migration

**Approach:** Iteratively migrate workloads to pull from Harbor proxy.

**Priority Order:**

1. **Test Workload** (new deployment for validation)
   - Deploy simple workload pulling from Harbor proxy
   - Verify image pull, caching, pod startup

2. **Non-Critical Services** (Grafana, monitoring exporters)
   - Low-risk, easy rollback
   - Validates Harbor performance under real load

3. **Platform Services** (Vault, Authentik, Gitea)
   - Mission-critical, but Harbor already operational
   - Update HelmRelease values to use Harbor proxy paths

4. **Infrastructure** (CNI, CSI, CoreDNS)
   - **Requires Talos reconfiguration** (node reboot)
   - Deploy during maintenance window
   - Thorough testing in dev/staging first

**Implementation Pattern:**

```yaml
# k8s/applications/<service>/helmrelease.yaml
spec:
  values:
    image:
      registry: registry.test-cluster.agentydragon.com/docker-hub-proxy
      repository: library/postgres
      tag: "16"
```

**GitOps Workflow:**

1. Update HelmRelease in git
2. `git add -A && git commit -m "feat(harbor): migrate <service> to Harbor proxy" && git push`
3. `flux reconcile source git <service>-chart -n <namespace>`
4. `flux reconcile helmrelease <service> -n <namespace>`
5. Verify pod restarts with new image source

**Rollback Plan:**

- Revert git commit
- Flux reconciles back to public registry
- Harbor remains operational for other workloads

---

### Phase 4: Configure Talos Registry Mirrors (Transparent Redirection)

**Objective:** Enable cluster-wide automatic Harbor usage without manifest changes.

**Implementation:**

Update Talos machine configuration in `terraform/01-infrastructure/talos.tf`:

```hcl
machine:
  registries:
    mirrors:
      docker.io:
        endpoints:
          - https://registry.test-cluster.agentydragon.com/docker-hub-proxy
          - https://registry-1.docker.io  # Fallback
      ghcr.io:
        endpoints:
          - https://registry.test-cluster.agentydragon.com/ghcr-proxy
          - https://ghcr.io  # Fallback
      quay.io:
        endpoints:
          - https://registry.test-cluster.agentydragon.com/quay-proxy
          - https://quay.io  # Fallback
      registry.k8s.io:
        endpoints:
          - https://registry.test-cluster.agentydragon.com/registry-k8s-proxy
          - https://registry.k8s.io  # Fallback
```

**Deployment:**

1. Update `talos.tf` with registry mirror configuration
2. `cd terraform && ./bootstrap.sh` (applies Talos config changes)
3. Nodes reboot and apply new containerd configuration
4. Verify mirror active: `talosctl -n <node-ip> get containerdconfig`

**Testing:**

```bash
# Deploy test pod with public image
kubectl run test-nginx --image=nginx:alpine --rm -it -- sh

# Check containerd logs for Harbor pull
talosctl -n 10.0.1.1 logs containerd | grep "registry.test-cluster"
```

**Impact:**

- All future image pulls automatically use Harbor
- Existing pods unaffected until restart/update
- Workloads with explicit registry paths (e.g., `docker.io/...`) still honored

---

### Phase 5: Ongoing Monitoring and Optimization

**Metrics to Track:**

1. **Cache Hit Rate:**
   - Harbor Prometheus metrics: `harbor_project_quota_usage_bytes`
   - Target: >80% cache hit rate after 1 week

2. **Storage Growth:**
   - Monitor PVC usage: `kubectl get pvc -n harbor`
   - Alert threshold: 80% full

3. **Image Pull Times:**
   - Compare before/after Harbor deployment
   - Expected improvement: 5-10x faster for cached images

4. **Upstream Registry Bandwidth:**
   - Reduced egress to Docker Hub, GHCR
   - Cost savings for metered egress (cloud providers)

**Prometheus Queries:**

```promql
# Harbor storage usage
sum(harbor_project_repo_total{project="docker-hub-proxy"})

# Pull request rate
rate(harbor_core_http_request_total{path=~"/v2/.*/blobs/.*"}[5m])
```

**Grafana Dashboard:**

- Use community Harbor dashboard or create custom dashboard
- Panels: cache hit rate, storage usage, pull latency, error rate

**Optimization Actions:**

1. **Increase Cache TTL** for stable images (e.g., base images like Alpine, Postgres)
2. **Garbage Collection Tuning** - Run during low-traffic hours
3. **Tag Retention Policies** - Keep last 10 versions of each image
4. **Replication Rules** - Pre-fetch critical images nightly

---

## 5. Benefits Analysis

### 1. Faster Deployments (Latency Reduction)

**Baseline:**

- Public registry (Docker Hub, GHCR): 500ms-5s per layer pull (depends on network)
- First pod startup: 10-30 seconds (image pull + container start)

**With Harbor Cache:**

- Harbor local cache: 10-50ms per layer (10-100x faster)
- Subsequent pod startups: 2-5 seconds (image already on node or fast Harbor pull)

**Real-World Impact:**

- Horizontal Pod Autoscaler (HPA) events: Faster scale-up response
- Rolling updates: Reduced deployment time
- CI/CD pipelines: Faster test/staging environment bootstraps

### 2. Offline Capability

**Scenario:** Internet outage or upstream registry unavailable (GitHub outage, DockerHub
maintenance)

**Without Harbor:**

- Cannot pull images → Cannot deploy/scale pods → Service disruption

**With Harbor:**

- Cached images available → Deployments continue normally
- Only new, uncached images affected

**Use Case:**

- Disaster recovery scenarios
- Network-isolated development environments
- Compliance requirements (data locality)

### 3. Vulnerability Scanning (Trivy Integration)

**Feature:** Harbor's built-in Trivy scanner automatically scans cached images.

**Benefits:**

- **Continuous Scanning:** Images scanned on push/pull
- **CVE Reporting:** Dashboard shows vulnerabilities per image
- **Policy Enforcement:** Block deployment of images with critical CVEs
  - Configure: Harbor Project → Policy → "Prevent vulnerable images from running"
- **Compliance:** Audit trail of scanned images for security reviews

**Example Policy:**

```yaml
# Harbor webhook to Slack on critical CVE detected
apiVersion: v1
kind: ConfigMap
metadata:
  name: harbor-webhook-policy
data:
  policy.json: |
    {
      "vulnerability": {
        "severity": "critical",
        "action": "notify"
      }
    }
```

### 4. Image Provenance Tracking

**Harbor Audit Logs:**

- Who pulled which image
- When was image last accessed
- Image push/pull history

**Use Cases:**

- **Security Incident Response:** "Which pods are running compromised image X?"
- **Compliance Audits:** "Prove all production images scanned within 24h"
- **Capacity Planning:** "Which images are most frequently pulled?"

**Access Logs:**

```bash
# Query Harbor audit logs via API
curl -u admin:${HARBOR_PASSWORD} \
  https://registry.test-cluster.agentydragon.com/api/v2.0/audit-logs \
  | jq '.[] | select(.operation == "pull")'
```

### 5. Bandwidth Reduction

**Upstream Registry Egress:**

- **Before Harbor:** Every pod pull = upstream request
- **After Harbor:** Only first pull per image = upstream request

**Example Calculation:**

- Cluster with 50 pods using PostgreSQL 16
- Image size: 300 MB
- **Without Harbor:** 50 × 300 MB = 15 GB egress
- **With Harbor:** 1 × 300 MB = 300 MB egress (50x reduction)

**Cost Impact:**

- Cloud provider egress costs: $0.08-0.12/GB
- DockerHub rate limits: Reduced pull count
- Network congestion: Less bandwidth competition

**Additional Benefits:**

- Faster cluster rebuild (destroy→bootstrap cycles)
- Reduced dependency on upstream registry SLA

---

## 6. Risks and Mitigations

### Risk 1: Harbor Unavailability Blocking Deployments

**Risk Description:**
If Harbor is down, new pod deployments requiring uncached images will fail.

**Likelihood:** Low (Harbor deployed with HA, monitored)

**Impact:** High (blocks deployments)

**Mitigations:**

1. **Containerd Registry Fallback:**
   - Configure upstream registry as secondary endpoint
   - Containerd automatically tries fallback on Harbor failure
   - Ensures deployments continue (with slower public registry pulls)

2. **Harbor High Availability:**
   - Deploy multiple Harbor core replicas (`core.replicas: 2+`)
   - Load-balanced via Kubernetes Service
   - Database (PostgreSQL) with backup/restore

3. **Pre-Warming Critical Images:**
   - CronJob to periodically pull critical images
   - Ensures cache populated for essential infrastructure
   - Reduces "cold start" failures

4. **Monitoring and Alerts:**
   - Prometheus alert: `harbor_core_up == 0`
   - PagerDuty/Slack notification on Harbor unhealthy
   - Grafana dashboard with Harbor health status

**Residual Risk:** Minimal - fallback mechanisms ensure service continuity.

---

### Risk 2: Storage Exhaustion

**Risk Description:**
Harbor registry storage PVC fills up, preventing new image caching.

**Likelihood:** Medium (depends on workload churn and retention policies)

**Impact:** Medium (degrades to upstream-only pulls, but doesn't block deployments if
fallback configured)

**Mitigations:**

1. **Capacity Monitoring:**
   - Prometheus alert: `harbor_registry_storage_usage > 0.8`
   - Grafana dashboard: Storage trend over time

2. **Automated Garbage Collection:**
   - Enable Harbor GC on schedule (daily 3 AM)
   - Removes untagged images and orphaned layers

   ```yaml
   # Harbor configuration
   jobservice:
     jobLoggers:
       - database
     maxJobWorkers: 10
     notifications:
       webhook_job_max_retry: 3
   ```

3. **Tag Retention Policies:**
   - Configure per-project: Keep last 10 versions
   - Automatically prune old image versions

4. **Dynamic PVC Expansion:**
   - Proxmox CSI supports online expansion
   - Manual expansion: `kubectl patch pvc harbor-registry -n harbor -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'`
   - Automate via Kubernetes Storage Resource Quota

5. **Storage Tier Strategy:**
   - Cold storage: Move infrequently accessed images to cheaper backend
   - Harbor supports S3-compatible backends (MinIO, Ceph)

**Residual Risk:** Low - proactive monitoring and automation prevent exhaustion.

---

### Risk 3: Image Sync Delays

**Risk Description:**
New upstream image version available, but Harbor cache still serves old version (stale cache).

**Likelihood:** Low (Harbor respects cache headers, configurable TTL)

**Impact:** Low (workloads may use slightly outdated images until cache refresh)

**Mitigations:**

1. **Immutable Tags and SHA Pinning:**
   - Use SHA digests in production: `image: nginx@sha256:abc123...`
   - Guarantees specific image version, bypasses cache staleness

2. **Manual Cache Invalidation:**
   - Harbor UI: Delete cached artifact to force re-pull
   - API: `DELETE /api/v2.0/projects/{project}/repositories/{repo}/artifacts/{tag}`

3. **Configurable Cache TTL:**
   - Harbor proxy cache respects upstream `Cache-Control` headers
   - Can set project-level TTL override if needed

4. **Pre-Release Image Warming:**
   - Before deploying new version, manually pull to Harbor
   - Ensures cache contains latest before production rollout

**Residual Risk:** Minimal - SHA pinning and immutable tags eliminate staleness concerns
for production.

---

### Risk 4: Bootstrap Chicken-and-Egg Problem

**Risk Description:**
Configuring Talos to use Harbor before Harbor is operational creates circular dependency.

**Likelihood:** High (if Talos reconfigured prematurely)

**Impact:** Critical (cluster cannot bootstrap)

**Mitigations:**

1. **Phased Rollout (THIS STRATEGY):**
   - Phase 1: Deploy Harbor using public registries
   - Phase 2-3: Migrate workloads to Harbor proxy (optional)
   - Phase 4: Configure Talos registry mirrors (with fallback)
   - **Harbor already operational before Talos reconfiguration**

2. **Talos Registry Mirror Fallback:**
   - Always configure upstream as secondary endpoint
   - Talos containerd falls back automatically if Harbor unreachable

3. **Bootstrap Script Logic:**
   - `./bootstrap.sh` checks Harbor health before applying Talos mirror config
   - Conditional: Only enable mirrors if Harbor API returns 200 OK

4. **Emergency Bypass:**
   - Keep Talos config without mirrors committed to git
   - Rollback available: Revert commit, apply clean Talos config

**Residual Risk:** Low - phased approach and fallback mechanisms prevent deadlock.

---

## 7. Implementation Checklist

### Prerequisites (Complete ✅)

- [x] Harbor deployed and accessible
- [x] TLS certificates configured
- [x] Admin credentials secured in Vault/ESO
- [x] Ingress routing functional

### Phase 2: Pull-Through Cache Setup

- [ ] Create registry endpoints in Harbor (Docker Hub, GHCR, Quay, registry.k8s.io)
- [ ] Create proxy cache projects for each registry
- [ ] Configure projects as public (no authentication required for pulls)
- [ ] Test manual pull through Harbor proxy
- [ ] Verify image cached in Harbor UI (Projects → docker-hub-proxy → Repositories)
- [ ] Document proxy URLs in cluster documentation

### Phase 3: Workload Migration (Gradual)

- [ ] Identify first test workload (low-risk service)
- [ ] Update HelmRelease to use Harbor proxy image path
- [ ] Commit, push, Flux reconcile
- [ ] Verify pod pulls from Harbor (check containerd logs)
- [ ] Repeat for 2-3 non-critical services
- [ ] Assess performance/reliability over 1 week
- [ ] Expand to platform services (Vault, Authentik, Gitea)
- [ ] Update docs/BOOTSTRAP.md with Harbor usage

### Phase 4: Talos Registry Mirrors (Infrastructure)

- [ ] PRE-FLIGHT CHECKS:
  - [ ] Harbor cache hit rate >80% for critical images
  - [ ] Harbor availability 99.9%+ over past week
  - [ ] Storage headroom >50% available
- [ ] Update `talos.tf` with registry mirror configuration
- [ ] Add fallback endpoints for all mirrors
- [ ] Test configuration in dev/staging cluster first (if available)
- [ ] Schedule maintenance window for Talos reconfiguration
- [ ] Apply terraform changes: `cd terraform && ./bootstrap.sh`
- [ ] Monitor node reboots and image pulls
- [ ] Verify containerd configuration: `talosctl get containerdconfig`
- [ ] Deploy test workload, confirm Harbor usage
- [ ] Document Talos mirror configuration in docs/BOOTSTRAP.md

### Phase 5: Post-Deployment Monitoring

- [ ] Deploy Prometheus ServiceMonitor for Harbor
- [ ] Create Grafana dashboard for Harbor metrics
- [ ] Configure Prometheus alerts
- [ ] Enable Harbor garbage collection cron
- [ ] Configure tag retention policies per project
- [ ] Test cache warmer CronJob (optional, if needed)
- [ ] Review Harbor audit logs monthly

### Ongoing Operations

- [ ] Weekly: Review Harbor storage trends
- [ ] Monthly: Analyze cache hit rates and optimize TTLs
- [ ] Quarterly: Evaluate Harbor HA/scaling needs
- [ ] Ad-hoc: Invalidate cache for specific images on security updates
- [ ] Annually: Review proxy project configurations and upstream registries

---

## 8. Alternative Approaches Considered

### Skopeo-based Image Mirroring

**Description:** Use Skopeo to periodically sync images from upstream to Harbor.

**Pros:** Complete control over synced images, true air-gap capability.

**Cons:** Complex automation, requires image inventory management, high maintenance.

**Verdict:** Over-engineered for typical use cases. Pull-through cache simpler and sufficient.

---

### Harbor Replication Rules

**Description:** Harbor's built-in replication feature to pull images on schedule.

**Pros:** Native Harbor feature, UI-configurable.

**Cons:** Still requires defining image list, not transparent to workloads.

**Verdict:** Useful for specific use cases (pre-warming known images), but pull-through
cache better default.

---

### External Harbor Instance (VM-based)

**Description:** Deploy Harbor on dedicated VM outside cluster.

**Pros:** No bootstrap chicken-and-egg, Harbor always available.

**Cons:** Requires separate VM management, defeats purpose of in-cluster registry.

**Verdict:** Valid for true production environments needing maximum reliability, but
unnecessary complexity for current scope.

---

### Multi-Cluster Harbor Federation

**Description:** Deploy Harbor in multiple clusters with cross-cluster replication.

**Pros:** Ultimate high availability and geo-distribution.

**Cons:** Extremely complex, requires Harbor Premium features.

**Verdict:** Future consideration if multiple production clusters deployed.

---

## 9. Success Metrics

**Short-term (1 week post-deployment):**

- Harbor proxy configured for 4+ upstream registries
- 10+ workloads pulling from Harbor proxy
- Cache hit rate >50%
- Zero deployment failures due to Harbor issues

**Medium-term (1 month post-deployment):**

- 80%+ of cluster workloads using Harbor
- Cache hit rate >80%
- Talos registry mirrors configured
- Grafana dashboard operational with metrics

**Long-term (3 months post-deployment):**

- 95%+ cache hit rate for critical images
- Measurable reduction in upstream registry bandwidth
- Harbor uptime >99.9%
- Trivy scanning all cached images with policy enforcement

**Business Metrics:**

- Reduced public registry rate limit incidents
- Faster deployment times (measured via CI/CD pipelines)
- Improved offline capability (tested via simulated outage)
- Security compliance (CVE scanning operational)

---

## 10. References and Resources

### Official Documentation

- Harbor Proxy Cache Configuration: <https://goharbor.io/docs/latest/administration/configure-proxy-cache/>
- Harbor Installation Guide: <https://goharbor.io/docs/latest/install-config/>
- Talos Registry Mirrors: <https://www.talos.dev/latest/reference/configuration/#machineregistries>

### Community Resources

- Harbor Helm Chart: <https://github.com/goharbor/harbor-helm>
- Harbor Terraform Provider: <https://github.com/goharbor/terraform-provider-harbor>
- Kubernetes Image Pull Optimization: <https://kubernetes.io/docs/concepts/containers/images/>

### Related Cluster Documentation

- `/home/agentydragon/code/cluster/docs/BOOTSTRAP.md` - Cluster deployment procedures
- `/home/agentydragon/code/cluster/docs/PLAN.md` - Project roadmap and Harbor status
- `/home/agentydragon/code/cluster/docs/TROUBLESHOOTING.md` - Harbor troubleshooting

### Harbor Metrics and Monitoring

- Harbor Prometheus Metrics: <https://goharbor.io/docs/latest/administration/metrics/>
- Grafana Harbor Dashboard: <https://grafana.com/grafana/dashboards/12866> (community)
