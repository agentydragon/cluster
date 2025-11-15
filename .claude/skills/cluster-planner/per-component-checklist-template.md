# Per-Component Validation Checklist Template

## Universal Pre-Deployment Checklist

Apply to ANY Kubernetes component

### Namespace & RBAC

- [ ] Target namespace exists and is properly labeled
- [ ] ServiceAccount created with minimal required permissions
- [ ] Role/ClusterRole defines least-privilege access
- [ ] RoleBinding/ClusterRoleBinding links SA to roles correctly
- [ ] No use of default ServiceAccount for applications
- [ ] RBAC tested: `kubectl auth can-i <verb> <resource> --as=system:serviceaccount:<namespace>:<sa>`

### Secrets & Configuration

- [ ] All required secrets exist and are accessible
- [ ] ConfigMaps contain valid configuration data
- [ ] No hardcoded passwords/tokens in manifests
- [ ] Secret references use correct keys
- [ ] Configuration syntax validated (YAML, JSON, etc.)
- [ ] Sensitive data properly base64 encoded in secrets

### Dependencies & Prerequisites

- [ ] All dependency components are READY (not just deployed)
- [ ] Required CRDs are installed and available
- [ ] Operator dependencies are running and healthy
- [ ] Database/storage dependencies are accessible
- [ ] Network dependencies can be reached

### Resource Requirements

- [ ] CPU/memory requests and limits defined appropriately
- [ ] Resource quotas in namespace allow the workload
- [ ] Node capacity sufficient for resource requests
- [ ] Storage requirements (PVCs) can be satisfied
- [ ] Ephemeral storage limits appropriate

### Networking

- [ ] Required ports are not already in use
- [ ] Network policies permit required communication
- [ ] DNS resolution works for dependencies
- [ ] LoadBalancer/Ingress configuration valid
- [ ] Service discovery properly configured

### Security Context

- [ ] Containers run as non-root user where possible
- [ ] SecurityContext defines appropriate user/group IDs
- [ ] No unnecessary privilege escalation
- [ ] PodSecurityPolicy/Pod Security Standards compliance
- [ ] ReadOnlyRootFilesystem where applicable

## Component Class-Specific Checklists

### CNI (Container Network Interface) Components

Examples: Cilium, Calico, Flannel, Weave

#### CNI Pre-Deployment

- [ ] **CNI BOOTSTRAP PARADOX CHECK**: Can CNI start without existing network?
- [ ] Host networking requirements met (kernel modules, iptables)
- [ ] Node OS compatibility verified (Linux kernel version)
- [ ] No conflicting CNI plugins already installed
- [ ] Required system directories exist (/etc/cni/net.d/, /opt/cni/bin/)

#### Network Post-Deployment Validation

- [ ] All nodes show Ready status
- [ ] Pod-to-pod communication works across nodes
- [ ] Service discovery and DNS resolution functional
- [ ] Network policies can be enforced (if applicable)
- [ ] Container logs accessible

### Storage Providers

Examples: Longhorn, Rook/Ceph, local-path, cloud storage classes

#### Storage Pre-Deployment

- [ ] **STORAGE BOOTSTRAP CHECK**: Can storage operator start without storage?
- [ ] Node storage capacity sufficient
- [ ] Block devices available and properly formatted (if required)
- [ ] Host filesystem permissions correct
- [ ] No conflicting storage providers

#### Storage Post-Deployment Validation

- [ ] StorageClass created and set as default (if intended)
- [ ] PVC creation and binding works
- [ ] Volume mounting in pods successful
- [ ] Read/write operations functional
- [ ] Backup and snapshot capabilities working (if applicable)

### Load Balancer Providers

Examples: MetalLB, cloud provider LBs, HAProxy

#### LoadBalancer Pre-Deployment

- [ ] **LB IP POOL DEFINED**: Available IP ranges configured
- [ ] Network infrastructure supports LoadBalancer IPs
- [ ] No IP conflicts with existing infrastructure
- [ ] BGP configuration correct (if using BGP mode)

#### LoadBalancer Post-Deployment Validation

- [ ] LoadBalancer services get external IPs assigned
- [ ] External connectivity to LoadBalancer IPs works
- [ ] Traffic distribution among backend pods functional
- [ ] Health checks properly configured

### Secret Management Systems

Examples: Vault, External Secrets Operator, Sealed Secrets

#### Secrets Pre-Deployment

- [ ] **SECRET CIRCULAR DEPENDENCY CHECK**: Can start without secrets it manages?
- [ ] Bootstrap secrets/initialization method defined
- [ ] Storage backend available and accessible
- [ ] Authentication method configured
- [ ] Network connectivity to external secret stores (if applicable)

#### Secrets Post-Deployment Validation

- [ ] Secret creation and retrieval works
- [ ] Secret rotation functional (if applicable)
- [ ] Audit logging enabled and working
- [ ] Backup and disaster recovery procedures tested
- [ ] Access controls properly enforced

### Certificate Management

Examples: cert-manager, Spiffe/Spire, manual certificate deployment

#### Certificates Pre-Deployment

- [ ] **DNS/ACME PROVIDER READY**: DNS provider accessible for challenges
- [ ] ACME account configured (if using Let's Encrypt)
- [ ] Webhook admission controller considerations
- [ ] Initial CA certificates available

#### Certificates Post-Deployment Validation

- [ ] Certificate issuance works for test domains
- [ ] Certificate renewal triggers properly
- [ ] ACME challenge completion successful
- [ ] Certificate validation passes in applications
- [ ] Certificate monitoring and alerting configured

### DNS Providers

Examples: PowerDNS, CoreDNS, external DNS controllers

#### DNS Pre-Deployment

- [ ] **DNS CIRCULAR DEPENDENCY CHECK**: Can start without DNS resolution?
- [ ] Authoritative DNS zones configured
- [ ] API credentials for DNS providers available
- [ ] Zone delegation properly configured

#### DNS Post-Deployment Validation

- [ ] DNS queries resolve correctly
- [ ] Zone transfers work (if applicable)
- [ ] API endpoints accessible for dynamic updates
- [ ] DNSSEC validation (if enabled)
- [ ] TTL and caching behavior appropriate

### Ingress Controllers

Examples: ingress-nginx, Traefik, HAProxy, Istio Gateway

#### Ingress Pre-Deployment

- [ ] **LOADBALANCER DEPENDENCY**: LoadBalancer or NodePort service available
- [ ] TLS certificate strategy defined
- [ ] Default backend service configured
- [ ] Ingress class properly defined

#### Ingress Post-Deployment Validation

- [ ] HTTP/HTTPS traffic routing works
- [ ] TLS termination functional
- [ ] Path-based and host-based routing correct
- [ ] Rate limiting and security policies active (if configured)
- [ ] Metrics and logging collection working

### Monitoring & Observability

Examples: Prometheus, Grafana, Jaeger, ElasticSearch

#### Monitoring Pre-Deployment

- [ ] **STORAGE REQUIREMENTS**: Sufficient storage for metrics/logs retention
- [ ] Service discovery configuration for targets
- [ ] Authentication/authorization strategy defined
- [ ] Network access to scraping targets

#### Monitoring Post-Deployment Validation

- [ ] Metrics collection from all intended targets
- [ ] Query interface accessible and functional
- [ ] Alert rules triggering appropriately
- [ ] Dashboard rendering correctly
- [ ] Data retention policies working

### Database Systems

Examples: PostgreSQL, MySQL, Redis, MongoDB operators

#### Database Pre-Deployment

- [ ] **PERSISTENT STORAGE**: Adequate storage with backup strategy
- [ ] Database initialization scripts/users prepared
- [ ] Network isolation and security configured
- [ ] Resource allocation appropriate for workload

#### Database Post-Deployment Validation

- [ ] Database connectivity from applications works
- [ ] Authentication and authorization functional
- [ ] Backup and restore procedures tested
- [ ] Performance monitoring active
- [ ] High availability setup verified (if applicable)

### Service Mesh Components

Examples: Istio, Linkerd, Consul Connect

#### ServiceMesh Pre-Deployment

- [ ] **CNI COMPATIBILITY**: Compatible with existing network setup
- [ ] Sidecar injection strategy defined
- [ ] mTLS certificate management configured
- [ ] Pilot/control plane redundancy planned

#### ServiceMesh Post-Deployment Validation

- [ ] Sidecar injection working correctly
- [ ] Service-to-service communication encrypted
- [ ] Traffic policies enforced
- [ ] Metrics and tracing data flowing
- [ ] Circuit breaking and retries functional

### CI/CD Systems

Examples: Tekton, Argo Workflows, Jenkins, GitLab Runner

#### CICD Pre-Deployment

- [ ] **BUILD ENVIRONMENT**: Container runtime and build tools available
- [ ] Source code repository access configured
- [ ] Artifact storage strategy defined
- [ ] Security scanning tools integrated

#### CICD Post-Deployment Validation

- [ ] Pipeline execution successful
- [ ] Source code checkout working
- [ ] Build artifact creation and storage functional
- [ ] Deployment to target environments working
- [ ] Security scanning and approval gates active

## Health Check Templates by Component Type

### Networking Components

```bash
# Connectivity test between pods
kubectl run test-net-1 --image=nicolaka/netshoot --rm -it -- ping <target-ip>

# DNS resolution test
kubectl run test-dns --image=busybox --rm -it -- nslookup kubernetes.default.svc.cluster.local

# Service reachability test
kubectl run test-svc --image=nicolaka/netshoot --rm -it -- curl <service>.<namespace>:port
```

### Storage Components

```bash
# PVC creation test
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 1Gi
EOF

# Mount and write test
# Storage test (abbreviated)
kubectl run test-storage --image=busybox --rm -it --restart=Never \
  --overrides='<STORAGE_TEST_CONFIG>' -- sh -c 'echo test > /data/test && cat /data/test'
```

### Security Components

```bash
# Secret accessibility test
# Secret test (abbreviated)
kubectl run test-secret --image=busybox --rm -it --restart=Never \
  --overrides='<SECRET_TEST_CONFIG>' -- sh -c 'echo $TEST_SECRET'

# RBAC verification
kubectl auth can-i <verb> <resource> --as=system:serviceaccount:<namespace>:<serviceaccount>
```

### Application Components

```bash
# Application readiness test
kubectl wait --for=condition=ready pod -l app=<app-name> --timeout=300s

# Application functionality test
kubectl run test-app --image=nicolaka/netshoot --rm -it -- curl http://<app-service>:port/health
```
