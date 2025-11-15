# Live Dependency Matrix

## Current Components Analysis

### Infrastructure Layer

| Component | Status | Dependencies | Dependents | Critical Path |
|-----------|---------|-------------|------------|---------------|
| Talos | ✓ DEPLOYED | Proxmox | All cluster components | YES |
| CNI | TBD | Talos | All pod networking | YES |
| Storage | TBD | Talos, CNI | Persistent workloads | YES |

### Security & Secrets Layer

| Component | Status | Dependencies | Dependents | Critical Path |
|-----------|---------|-------------|------------|---------------|
| cert-manager | TBD | CNI, DNS | HTTPS services | YES |
| Vault | TBD | Storage, CNI | Secret management | PARTIAL |
| External Secrets | TBD | Vault, CNI | Applications | NO |

### Platform Services Layer

| Component | Status | Dependencies | Dependents | Critical Path |
|-----------|---------|-------------|------------|---------------|
| Ingress Controller | TBD | CNI, cert-manager | Web services | YES |
| DNS (PowerDNS) | TBD | Storage, CNI | cert-manager, external access | YES |
| Monitoring | TBD | Storage, CNI | Observability | NO |

### Applications Layer

| Component | Status | Dependencies | Dependents | Critical Path |
|-----------|---------|-------------|------------|---------------|
| Authentik SSO | TBD | Ingress, cert-manager, storage | All authenticated services | YES |
| Gitea | TBD | SSO, storage, ingress | CI/CD, repo management | PARTIAL |
| Harbor | TBD | SSO, storage, ingress | Container registry | NO |
| Matrix | TBD | SSO, storage, ingress | Communications | NO |

## Circular Dependency Alerts

🔄 **DETECTED**: cert-manager → DNS (PowerDNS) → TLS certificates → cert-manager
🔄 **POTENTIAL**: Vault → TLS → cert-manager → DNS → Vault

## Bootstrap Strategy Required

- **Phase 1**: Infrastructure (Talos, CNI, Storage)
- **Phase 2**: DNS with temporary certs or HTTP
- **Phase 3**: cert-manager with DNS integration
- **Phase 4**: Vault and secrets management
- **Phase 5**: Platform services and applications
