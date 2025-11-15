# Common Kubernetes Deployment Pitfalls Checklist

## Critical Infrastructure Pitfalls

### CNI (Container Networking) Bootstrap Paradox

- [ ] **PITFALL**: CNI managed by operator that requires CNI to work
- [ ] **CHECK**: Can CNI start without external dependencies?
- [ ] **SOLUTION**: Use static manifests for CNI, not operators during bootstrap
- [ ] **VALIDATION**: Pods can communicate before any operators start

### CoreDNS Circular Dependencies

- [ ] **PITFALL**: External DNS operator needs DNS to resolve API endpoints
- [ ] **CHECK**: Can CoreDNS start with static configuration?
- [ ] **SOLUTION**: Bootstrap CoreDNS with file-based zones, migrate to dynamic later
- [ ] **VALIDATION**: `nslookup kubernetes.default.svc.cluster.local` works

### Storage Bootstrap Chicken-Egg

- [ ] **PITFALL**: Storage operator needs PVC but provides storage
- [ ] **CHECK**: Does storage solution need itself to bootstrap?
- [ ] **SOLUTION**: Use local-path or hostPath for operator, migrate data later
- [ ] **VALIDATION**: Operator pods start and create StorageClass

## CRD and Webhook Timing Issues

### CRD Installation Timing

- [ ] **PITFALL**: Creating custom resources before CRDs exist
- [ ] **CHECK**: Are CRDs applied before custom resources?
- [ ] **SOLUTION**: Use Flux/ArgoCD dependencies or kubectl wait
- [ ] **VALIDATION**: `kubectl get crd` shows all required CRDs

### ValidatingAdmissionWebhook Readiness

- [ ] **PITFALL**: Creating resources before webhook is ready
- [ ] **CHECK**: Is webhook healthy before dependent resources?
- [ ] **SOLUTION**: Use readiness probes and explicit waits
- [ ] **VALIDATION**: `kubectl get validatingwebhookconfigurations` shows ready

### Operator vs Instance Confusion

- [ ] **PITFALL**: Deploying instance before operator
- [ ] **CHECK**: Is operator pod running before creating CR instances?
- [ ] **SOLUTION**: Split into operator phase + instance phase
- [ ] **VALIDATION**: `kubectl get pods -n operator-namespace` shows running

## Secret Management Pitfalls

### Secret Circular Dependencies

- [ ] **PITFALL**: Vault needs TLS cert, cert-manager needs Vault secrets
- [ ] **CHECK**: Can each secret system bootstrap independently?
- [ ] **SOLUTION**: Use bootstrap secrets, migrate to proper management later
- [ ] **VALIDATION**: Each system starts with temporary/bootstrap secrets

### Default ServiceAccount Overprivilege

- [ ] **PITFALL**: Using default SA with cluster-admin
- [ ] **CHECK**: Does each component have minimal RBAC?
- [ ] **SOLUTION**: Create dedicated SAs with least privilege
- [ ] **VALIDATION**: `kubectl auth can-i --list --as=system:serviceaccount:ns:sa`

### Hardcoded Secrets in Manifests

- [ ] **PITFALL**: Passwords/tokens directly in YAML
- [ ] **CHECK**: Are all secrets externalized or generated?
- [ ] **SOLUTION**: Use External Secrets, SealedSecrets, or generators
- [ ] **VALIDATION**: `grep -r "password\|token" manifests/` finds no literals

## Namespace and RBAC Pitfalls

### Namespace Creation Order

- [ ] **PITFALL**: Deploying to namespace before it exists
- [ ] **CHECK**: Are namespaces created before resources?
- [ ] **SOLUTION**: Explicit namespace creation in dependency order
- [ ] **VALIDATION**: `kubectl get namespace` shows all required namespaces

### Cross-Namespace Service Access

- [ ] **PITFALL**: Services can't reach across namespaces
- [ ] **CHECK**: Are FQDN service names used? (service.namespace.svc.cluster.local)
- [ ] **SOLUTION**: Use full DNS names or create cross-namespace policies
- [ ] **VALIDATION**: `kubectl exec -it pod -- nslookup service.other-ns.svc.cluster.local`

### PodSecurityPolicy/PodSecurity Violations

- [ ] **PITFALL**: Pods fail to start due to security policy
- [ ] **CHECK**: Do pods comply with cluster security standards?
- [ ] **SOLUTION**: Adjust securityContext or namespace security policy
- [ ] **VALIDATION**: Pods start without security policy violations

## Network and Connectivity Pitfalls

### LoadBalancer Without MetalLB/Cloud Provider

- [ ] **PITFALL**: Services stay pending without LoadBalancer implementation
- [ ] **CHECK**: Is LoadBalancer provider (MetalLB) deployed first?
- [ ] **SOLUTION**: Deploy MetalLB before services needing LoadBalancer
- [ ] **VALIDATION**: `kubectl get svc` shows EXTERNAL-IP assigned

### Ingress Without Controller

- [ ] **PITFALL**: Ingress objects created before controller exists
- [ ] **CHECK**: Is ingress controller deployed and ready?
- [ ] **SOLUTION**: Deploy ingress-nginx/traefik before Ingress objects
- [ ] **VALIDATION**: `kubectl get ingressclass` shows available class

### NetworkPolicy Lockout

- [ ] **PITFALL**: NetworkPolicies block essential cluster communication
- [ ] **CHECK**: Do policies allow CoreDNS, kubelet, CNI communication?
- [ ] **SOLUTION**: Start permissive, incrementally restrict
- [ ] **VALIDATION**: Core cluster functions work after policy application

## Storage and Persistence Pitfalls

### PVC Without StorageClass

- [ ] **PITFALL**: PVCs pending due to missing StorageClass
- [ ] **CHECK**: Is default StorageClass available?
- [ ] **SOLUTION**: Deploy storage provider before PVCs
- [ ] **VALIDATION**: `kubectl get storageclass` shows default class

### Volume Mount Permissions

- [ ] **PITFALL**: Pods can't write to volumes due to ownership
- [ ] **CHECK**: Do securityContext UIDs match volume ownership?
- [ ] **SOLUTION**: Use initContainers to fix permissions or fsGroup
- [ ] **VALIDATION**: Pod can read/write mounted volumes

### StatefulSet Ordering Dependencies

- [ ] **PITFALL**: StatefulSet pods start before dependencies ready
- [ ] **CHECK**: Are readiness probes preventing premature ready state?
- [ ] **SOLUTION**: Proper readiness probes + init containers
- [ ] **VALIDATION**: Pods only become ready when actually functional

## Resource and Scheduling Pitfalls

### Node Affinity Conflicts

- [ ] **PITFALL**: Pods can't schedule due to affinity constraints
- [ ] **CHECK**: Do nodes have required labels/taints?
- [ ] **SOLUTION**: Label nodes or adjust affinity rules
- [ ] **VALIDATION**: `kubectl describe pod` shows successful scheduling

### Resource Quota Violations

- [ ] **PITFALL**: Pods fail to schedule due to resource limits
- [ ] **CHECK**: Are namespace quotas sufficient for workload?
- [ ] **SOLUTION**: Adjust quotas or resource requests
- [ ] **VALIDATION**: Pods schedule without quota violations

### DaemonSet Node Compatibility

- [ ] **PITFALL**: DaemonSets don't run on all expected nodes
- [ ] **CHECK**: Do nodes meet DaemonSet requirements (OS, arch, labels)?
- [ ] **SOLUTION**: Adjust nodeSelector or add tolerations
- [ ] **VALIDATION**: `kubectl get ds -o wide` shows expected replica count

## Certificate and TLS Pitfalls

### Certificate Issuer Not Ready

- [ ] **PITFALL**: Certificates pending due to issuer problems
- [ ] **CHECK**: Is ClusterIssuer/Issuer in Ready state?
- [ ] **SOLUTION**: Debug issuer configuration (DNS, credentials)
- [ ] **VALIDATION**: `kubectl get clusterissuer` shows Ready=True

### TLS Certificate Chain Issues

- [ ] **PITFALL**: Applications reject certificates due to chain problems
- [ ] **CHECK**: Are intermediate certificates included?
- [ ] **SOLUTION**: Configure cert-manager for full chain
- [ ] **VALIDATION**: `openssl s_client -connect service:443 -verify_return_error`

### Certificate Renewal Failures

- [ ] **PITFALL**: Certificates expire due to renewal issues
- [ ] **CHECK**: Can cert-manager renew certificates?
- [ ] **SOLUTION**: Monitor cert-manager logs and fix ACME challenges
- [ ] **VALIDATION**: Certificates automatically renew before expiry

## Monitoring and Observability Pitfalls

### Missing Health Checks

- [ ] **PITFALL**: Kubernetes thinks pods are ready when they're not
- [ ] **CHECK**: Do readiness probes actually validate service functionality?
- [ ] **SOLUTION**: Implement meaningful health check endpoints
- [ ] **VALIDATION**: Readiness probe failures prevent traffic routing

### Log Collection Circular Dependencies

- [ ] **PITFALL**: Log collector needs logs to debug its own failures
- [ ] **CHECK**: Can you debug log collector without its own logs?
- [ ] **SOLUTION**: Start with simple logging, add complexity later
- [ ] **VALIDATION**: Basic pod logs accessible via kubectl

### Metrics Collection Missing Dependencies

- [ ] **PITFALL**: Prometheus can't scrape due to network/RBAC issues
- [ ] **CHECK**: Can Prometheus reach all targets?
- [ ] **SOLUTION**: Verify NetworkPolicies and ServiceMonitor configs
- [ ] **VALIDATION**: Prometheus targets show UP status

## Upgrade and Maintenance Pitfalls

### API Version Deprecation

- [ ] **PITFALL**: Manifests use deprecated API versions
- [ ] **CHECK**: Are all API versions current for target k8s version?
- [ ] **SOLUTION**: Update manifests before cluster upgrade
- [ ] **VALIDATION**: `kubectl apply --dry-run` succeeds

### Backup Strategy Missing

- [ ] **PITFALL**: No way to recover from deployment failures
- [ ] **CHECK**: Can you restore cluster state after failure?
- [ ] **SOLUTION**: Implement ETCD backups and disaster recovery
- [ ] **VALIDATION**: Restore procedure tested and documented

### Rolling Update Failures

- [ ] **PITFALL**: Deployments fail to update due to resource constraints
- [ ] **CHECK**: Are rolling update parameters appropriate?
- [ ] **SOLUTION**: Adjust maxUnavailable/maxSurge settings
- [ ] **VALIDATION**: Deployments update without service interruption

## Critical Pre-Deployment Checklist

### Before ANY Component Deployment

- [ ] Namespace exists and is labeled correctly
- [ ] RBAC (ServiceAccount, Role, RoleBinding) exists
- [ ] Required secrets exist and are accessible
- [ ] Dependencies are READY (not just deployed)
- [ ] Resource quotas allow the workload
- [ ] Network policies permit required communication
- [ ] Storage requirements are met
- [ ] Node requirements are satisfied (labels, taints, OS)

### Before Operator Deployment

- [ ] CRDs are defined and available
- [ ] Operator has cluster/namespace permissions
- [ ] Webhook certificates are managed (if applicable)
- [ ] Operator dependencies (storage, network) are ready

### Before Custom Resource Creation

- [ ] Operator is running and ready
- [ ] Webhooks are accessible and functional
- [ ] Required secrets/configmaps exist
- [ ] Namespace resource quotas sufficient
