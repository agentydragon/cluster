# SRE Tools and Techniques for Cluster Planning

## Google SRE 20-Year Veteran Methodology

### What I Always Do (Non-Negotiable)

#### 1. Start with SLOs Before Any Code

```bash
# Define reliability targets first
cat > cluster-slos.yaml <<EOF
reliability_targets:
  cluster_availability: 99.9%  # 8.76h downtime/year max
  deployment_success_rate: 99%  # 1% can fail
  mttr: 10m  # Mean time to recovery
  change_failure_rate: 5%  # 5% of changes can cause incidents
EOF
```

#### 2. Error Budget Planning

- **Burn Rate Analysis**: How fast are we consuming error budget?
- **Release Velocity**: Can only deploy when error budget allows
- **Incident Response**: Stop feature work when error budget exhausted

#### 3. Everything in Git, Everything Declarative

```bash
# Never manual kubectl commands in production
git log --oneline  # Every change tracked
terraform plan     # Infrastructure changes previewed
flux diff         # Kubernetes changes validated
```

#### 4. Golden Signal Monitoring From Day 1

```yaml
golden_signals:
  latency: p99 < 100ms
  traffic: requests/second
  errors: error_rate < 1%
  saturation: cpu < 80%, memory < 80%
```

### Essential SRE Tools I Always Use

#### Dependency Analysis and Planning

```bash
# 1. Dependency Graph Analysis
graphviz/dot                  # Visualize dependency graphs
mermaid-cli                  # Generate diagrams from text
kubectl-tree                 # Show Kubernetes object relationships
kubectl-graph               # Visualize resource relationships

# 2. Configuration Validation
kubeconform                 # Validate Kubernetes YAML
kubeval                     # Schema validation
polaris                     # Best practices checking
pluto                       # Find deprecated APIs
conftest                    # Policy enforcement
```

#### Cluster Health Assessment

```bash
# 3. Rapid Health Checks
kubectl get nodes -o wide
kubectl get pods -A --field-selector=status.phase!=Running
kubectl get events -A --sort-by='.firstTimestamp' | tail -20
kubectl top nodes
kubectl top pods -A

# 4. Component-Specific Debugging
cilium status              # CNI health
crictl ps                  # Container runtime
systemctl status kubelet  # Node agent health
```

#### Source Code Analysis for Debugging

```bash
# 5. Clone and Analyze Source Code
# Structure: /mnt/tankshare/code/domain.tld/org/repo
find /mnt/tankshare/code -name "*.go" -exec grep -l "flag.String\|flag.Int\|log.level\|debug" {} \;
rg "config\.|viper\.|flag\." --type go  # Find configuration options
rg "log\..*level\|debug\|trace" --type go  # Find debug options
```

#### Production-Grade Validation Tools

```bash
# 6. Chaos Engineering and Testing
kubectl run chaos-test --rm -i --image=nicolaka/netshoot
kubectl apply -f https://github.com/chaos-mesh/chaos-mesh/releases/download/v2.5.0/chaos-mesh-v2.5.0.yaml

# 7. Security and Compliance
falco                       # Runtime security monitoring
kube-bench                 # CIS Kubernetes benchmark
kube-hunter                # Penetration testing
kubectl-who-can           # RBAC analysis
```

### What I Never Waste Time On

#### ❌ Manual Configuration Management

- Never edit live objects with `kubectl edit`
- Never store configuration in local files
- Never rely on "tribal knowledge" for configuration

#### ❌ Reactive Monitoring

- Never wait for users to report problems
- Never monitor vanity metrics that don't correlate with user experience
- Never set up monitoring without alerting thresholds

#### ❌ Perfect Upfront Design

- Never try to plan every detail before starting
- Never assume requirements won't change
- Never optimize before measuring

#### ❌ Hero Engineering

- Never accept single points of human failure
- Never skip documentation because "I'll remember"
- Never bypass process for "quick fixes"

### Advanced SRE Techniques

#### 1. Dependency Criticality Matrix

```yaml
# Classify dependencies by impact and probability
dependencies:
  networking:
    impact: critical      # Cluster unusable without
    mtbf: 8760h          # Mean time between failures
    mttr: 5m             # Recovery time

  storage:
    impact: high         # Some workloads affected
    mtbf: 2160h
    mttr: 15m

  monitoring:
    impact: medium       # Reduced observability
    mtbf: 720h
    mttr: 10m
```

#### 2. Change Velocity vs Reliability Analysis

```python
# Deployment frequency impact on reliability
deployment_frequency = "daily"  # vs weekly, monthly
change_size = "small"           # vs medium, large
error_budget_consumption = calculate_risk(deployment_frequency, change_size)
```

#### 3. Capacity Planning with Growth Projections

```bash
# Resource usage trending
kubectl top nodes --sort-by=cpu
kubectl top pods -A --sort-by=cpu | head -20

# Growth rate analysis
prometheus_query='rate(container_cpu_usage_seconds_total[7d])'
grafana_dashboard="cluster-capacity-planning"
```

### Source Code Research Protocol

#### When Any Component Fails

```bash
# 1. Clone source if not exists
COMPONENT="vault"  # example
REPO_PATH="/mnt/tankshare/code/github.com/hashicorp/${COMPONENT}"

if [ ! -d "$REPO_PATH" ]; then
    mkdir -p "$(dirname "$REPO_PATH")"
    git clone "https://github.com/hashicorp/${COMPONENT}.git" "$REPO_PATH"
fi

# 2. Find configuration options
rg "flag\.|config\.|env\." --type go "$REPO_PATH"
rg "log.*level\|debug\|trace" --type go "$REPO_PATH"

# 3. Find debug endpoints
rg "debug\|pprof\|metrics\|health" --type go "$REPO_PATH"
rg "http\.HandleFunc\|mux\.Handle" --type go "$REPO_PATH"

# 4. Study deployment manifests in source
find "$REPO_PATH" -name "*.yaml" -o -name "*.yml" | grep -E "(deploy|k8s|kubernetes)"
```

#### Configuration Discovery Pattern

```bash
# Standard places to look for config options
find "$REPO_PATH" -path "*/cmd/*" -name "*.go"  # CLI flags
find "$REPO_PATH" -path "*/config/*" -name "*.go"  # Config structs
find "$REPO_PATH" -name "values.yaml"  # Helm defaults
find "$REPO_PATH" -name "*.env*"  # Environment examples
```

### Reliability Engineering Decision Framework

#### Always Ask These Questions

1. **What's the blast radius if this fails?**
2. **How do we detect failure within 1 minute?**
3. **Can we rollback in under 10 minutes?**
4. **What's our error budget impact?**
5. **Is this change reversible?**

#### Before Any Deployment

```bash
# Pre-flight checklist
kubectl auth can-i create deployments --as=system:serviceaccount:namespace:sa
kubectl apply --dry-run=server -f manifests/
terraform plan -detailed-exitcode
helm template . --debug | kubeconform -strict

# Canary validation
kubectl apply -f canary-deployment.yaml
kubectl wait --for=condition=ready pod -l version=canary --timeout=300s
```

### Emergency Response Toolkit

#### When Cluster is Broken

```bash
# 1. Immediate assessment (30 seconds)
kubectl cluster-info dump --output-directory=/tmp/cluster-state
kubectl get nodes --no-headers | grep -v Ready

# 2. Component health (60 seconds)
kubectl get pods -n kube-system
kubectl get pods -n flux-system
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50

# 3. Recent changes (120 seconds)
git log --oneline --since="2 hours ago"
kubectl get events -A --sort-by='.firstTimestamp' | tail -50

# 4. Resource exhaustion check
kubectl top nodes
kubectl describe nodes | grep -A 10 "Allocated resources"
```

#### Debugging Decision Tree

```
Pod not starting?
├─ Check node capacity → kubectl describe nodes
├─ Check image pull → kubectl describe pod
├─ Check RBAC → kubectl auth can-i
└─ Check dependencies → kubectl get all -A

Service not reachable?
├─ Check endpoints → kubectl get endpoints
├─ Check network policies → kubectl get netpol -A
├─ Check DNS → nslookup service.namespace
└─ Check ingress → kubectl get ing -A

Storage not mounting?
├─ Check PVC status → kubectl describe pvc
├─ Check storage class → kubectl get sc
├─ Check node storage → df -h /var/lib
└─ Check CSI driver → kubectl get csidrivers
```

### SRE Metrics That Actually Matter

#### For Cluster Planning

```yaml
planning_metrics:
  mean_time_to_deploy: 15m      # How long to deploy new component
  change_failure_rate: 5%       # Percentage of deployments that fail
  recovery_time: 10m            # Time to fix failed deployment
  dependency_discovery_time: 2h # Time to understand component deps
```

#### For Operational Excellence

```yaml
operational_metrics:
  incident_response_time: 5m    # Time to acknowledge incident
  mttr_cluster_wide: 15m        # Mean time to recovery
  deployment_frequency: daily   # How often we can safely deploy
  error_budget_consumption: 20% # Percentage of monthly budget used
```

This represents 20 years of hard-won experience: automate everything, measure what matters, plan for failure, and always have a way back.
