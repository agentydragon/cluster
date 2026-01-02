# VPS Cluster Integration Plan

**Goal**: Extend the Talos cluster to include a VPS node, creating a geographically
distributed cluster that handles public ingress, DNS, and website hosting directly.

## Current Architecture

```text
Internet → VPS (nginx proxy) → Tailscale VPN → Home Cluster (Proxmox)
                                                    ├── 3 controllers
                                                    └── 2 workers
```

**Current VPS Role** (standalone, not in cluster):

- nginx SNI passthrough proxy
- PowerDNS secondary (AXFR from cluster)
- Tailscale relay for cluster traffic

**Limitations**:

- VPS is a single point of failure for ingress
- PowerDNS on VPS is secondary-only (can't create records directly)
- Website hosting requires separate infrastructure
- No pod scheduling on VPS resources

## Target Architecture

```text
Internet → VPS (Talos worker, cluster member)
              ├── Ingress Controller (receives public traffic)
              ├── PowerDNS (primary for *.agentydragon.com)
              ├── Website pods
              └── Tailscale mesh → Home Cluster (Proxmox)
                                       ├── 3 controllers
                                       └── 2+ workers
```

**VPS becomes**:

- Talos worker node in the same cluster
- Runs ingress-nginx with public IP
- Runs PowerDNS as primary authoritative server
- Hosts website and public-facing services
- Connected to home nodes via Tailscale mesh

## Benefits

1. **Unified Management**: Single cluster, single GitOps flow
2. **Geographic Distribution**: Services can run where they make sense
3. **Direct Ingress**: No proxy layer, native Kubernetes ingress
4. **Flexible Scheduling**: Some pods on VPS (public), some at home (storage-heavy)
5. **HA DNS**: PowerDNS can run on multiple nodes
6. **Simplified Architecture**: Remove nginx proxy layer

## Implementation Phases

### Phase 0: Prerequisites

- [ ] **VPS Selection**: New VPS or repurpose existing?
  - Option A: New VPS dedicated to Talos
  - Option B: Migrate existing VPS to Talos (requires downtime)
- [ ] **Network Planning**:
  - VPS public IP for ingress
  - Tailscale mesh connectivity to home nodes
  - Pod CIDR allocation for VPS node
- [ ] **Terraform State Backup**: Set up rclone to Google Drive before major changes
  - [ ] Configure rclone with Google Drive
  - [ ] Create backup script and cron job
  - [ ] Document recovery procedure

### Phase 1: VPS Talos Node

- [ ] **Provision VPS with Talos**
  - Talos image for cloud/VPS (not Proxmox QEMU)
  - Machine config with Tailscale extension
  - Worker role (not controller - keep controllers at home for latency)
- [ ] **Join Existing Cluster**
  - Generate machine config from existing cluster secrets
  - Configure Tailscale for mesh connectivity
  - Verify node joins and becomes Ready
- [ ] **Validate Connectivity**
  - Pods on VPS can reach pods at home
  - CoreDNS resolution works across nodes
  - Cilium networking healthy

### Phase 2: Migrate Ingress

- [ ] **Deploy ingress-nginx on VPS**
  - Node selector/affinity for VPS node
  - Use VPS public IP (hostNetwork or cloud LB)
  - Configure for public traffic
- [ ] **DNS Cutover**
  - Point *.agentydragon.com to VPS public IP
  - Keep old nginx running as fallback initially
- [ ] **Certificate Management**
  - cert-manager on VPS node
  - DNS-01 challenges (PowerDNS API)
- [ ] **Validate**
  - HTTPS traffic flows through VPS ingress
  - All existing services accessible
  - Decommission old nginx proxy

### Phase 3: Migrate PowerDNS

- [ ] **PowerDNS on VPS Worker**
  - Schedule PowerDNS pods on VPS node
  - Configure as primary authoritative
  - external-dns updates directly
- [ ] **Update DNS Delegation**
  - NS records point to VPS PowerDNS
  - Remove AXFR secondary setup
- [ ] **Validate**
  - DNS queries served from VPS
  - Record creation via external-dns works
  - cert-manager DNS-01 challenges succeed

### Phase 4: Website & Services

- [ ] **agentydragon.com Website**
  - Deploy website pods (static or SSG)
  - Ingress configuration
  - HTTPS via cert-manager
- [ ] **Public Service Migration**
  - Identify services that should run on VPS
  - Configure node affinity/scheduling
  - Update ingress rules
- [ ] **Home-Only Services**
  - Storage-heavy services stay at home (Harbor cache, Vault storage)
  - Configure pod anti-affinity for VPS

### Phase 5: Cleanup & Documentation

- [ ] **Decommission Old VPS Config**
  - Remove nginx proxy Ansible roles
  - Remove PowerDNS secondary config
  - Archive old configurations
- [ ] **Update Documentation**
  - docs/bootstrap.md for multi-node cluster
  - docs/operations.md for VPS node management
  - Architecture diagrams
- [ ] **Monitoring & Alerting**
  - VPS node health monitoring
  - Cross-site latency metrics
  - Alerting for VPS node issues

## Technical Considerations

### Networking

**Tailscale Mesh**:

- Controllers and workers connect via Tailscale
- Pod-to-pod traffic crosses Tailscale tunnel
- Cilium must handle cross-node routing

**Public IP Handling**:

- VPS has public IP directly
- ingress-nginx binds to public IP (hostNetwork: true or externalTrafficPolicy)
- MetalLB not needed on VPS (cloud has native LB or direct IP)

### Storage

**VPS Storage**:

- Limited local storage on VPS
- No Proxmox CSI (different hypervisor)
- Options: local-path-provisioner, cloud block storage, or no persistent storage

**Home Storage**:

- Proxmox CSI for persistent volumes
- Services needing storage should run at home
- Consider NFS for shared access

### Scheduling

**Node Labels**:

```yaml
# VPS node
topology.kubernetes.io/zone: vps
node.kubernetes.io/instance-type: vps

# Home nodes
topology.kubernetes.io/zone: home
node.kubernetes.io/instance-type: proxmox-vm
```

**Pod Placement Examples**:

```yaml
# Public services on VPS
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: topology.kubernetes.io/zone
          operator: In
          values: [vps]

# Storage services at home
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: topology.kubernetes.io/zone
          operator: In
          values: [home]
```

### Failure Modes

**VPS Outage**:

- Public ingress unavailable
- DNS queries fail (if PowerDNS only on VPS)
- Home services still running, just not publicly accessible
- Mitigation: HA PowerDNS across zones, health checks

**Home Outage**:

- Controllers unavailable (if all at home)
- VPS worker loses control plane connectivity
- Mitigation: Consider one controller on VPS? (latency concerns)

**Tailscale Outage**:

- Cross-site pod communication fails
- VPS can still serve cached data
- Home cluster functions independently

## Open Questions

1. **New VPS or migrate existing?**
   - New: Clean slate, no downtime
   - Migrate: Cost savings, requires careful planning

2. **Controller placement?**
   - All controllers at home: simpler, lower latency for etcd
   - One controller on VPS: more resilient, etcd latency concerns

3. **Storage strategy for VPS?**
   - No persistent storage (stateless services only)
   - Cloud block storage (vendor-specific)
   - NFS from home (latency)

4. **Gradual or big-bang migration?**
   - Gradual: Lower risk, more complexity
   - Big-bang: Cleaner, requires downtime window

## Related Tasks

From todo list:

- [ ] Set up rclone with Google Drive (terraform state backup)
- [ ] Create backup script and cron
- [ ] Update NixOS hosts with nix-cache key

## References

- Current cluster: `docs/plan.md`
- Bootstrap procedure: `docs/bootstrap.md`
- Talos documentation: <https://www.talos.dev/>
- Cilium multi-cluster: <https://docs.cilium.io/en/stable/network/clustermesh/>
