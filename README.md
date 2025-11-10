# Talos Cluster Configuration

This repository contains the complete configuration for a Talos Kubernetes cluster with SSO integration.

## Structure

```
cluster/
├── terraform/           # VM infrastructure (Proxmox/Talos VMs)
├── k8s/                # GitOps manifests (managed by Flux)
├── sso-terraform/      # SSO-specific Terraform modules (managed by tofu-controller)
└── flux-bootstrap.yaml # Flux bootstrap configuration
```

## Deployment

### 1. VM Infrastructure
```bash
cd terraform/
./tf.sh plan
./tf.sh apply
```

### 2. Flux Bootstrap
```bash
flux bootstrap git \
  --url=https://github.com/agentydragon/cluster \
  --branch=main \
  --path=./k8s
```

### 3. SSO Setup
Once Flux is bootstrapped, it will automatically:
1. Deploy tofu-controller
2. Generate SSO secrets via Terraform
3. Configure Vault authentication  
4. Set up Authentik with groups and property mappings
5. Configure OIDC providers for Harbor, Gitea, and Matrix

## Services

- **Vault**: Secret management and authentication backend
- **Authentik**: Identity provider with OIDC/OAuth2 support
- **Harbor**: Container registry with vulnerability scanning
- **Gitea**: Git service with web interface
- **Matrix**: Decentralized chat and collaboration

## External Access

Services are exposed via:
- **NodePort**: Services bind to cluster node ports
- **VPS Proxy**: External VPS reverse proxy for HTTPS termination
- **Let's Encrypt**: Automatic certificate generation via DNS challenges
- **Tailscale**: VPN access to cluster nodes

## Dependencies

The SSO services have careful dependency ordering:
1. **Secrets**: Generate client secrets and tokens (Terraform)
2. **Vault**: Configure authentication and secret storage (Terraform)  
3. **Authentik**: Set up identity provider with groups (Terraform)
4. **Services**: Configure OIDC providers for each service (Terraform)

All dependencies are managed automatically by Flux using Kustomization dependencies and tofu-controller.