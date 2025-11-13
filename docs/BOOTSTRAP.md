# Talos Cluster Bootstrap Playbook

This document provides step-by-step instructions for cold-starting the Talos cluster from nothing and managing individual nodes.

## Cold-Start Cluster Deployment

### Prerequisites
- Proxmox host (`atlas`) accessible via SSH
- Ansible vault configured with API tokens
- `direnv` configured in cluster directory
- VPS with nginx and PowerDNS configured via Ansible
- Access to AWS Route 53 for `agentydragon.com`

### Step 1: Fully Declarative Deployment
```bash
cd terraform/infrastructure
terraform apply
```

This handles:
- QCOW2 disk image from Talos Image Factory with baked-in static IP configuration
- VM creation with pre-configured networking
- Talos machine configuration application
- Kubernetes cluster initialization and bootstrap
- **Automated cluster health checks** (controllers, VIP, Kubernetes APIs)
- **Auto-generated kubeconfig** pointing to VIP for HA kubectl access

Terraform will automatically verify cluster health and fail if any issues are detected.

### Step 2: Setup GitOps with Flux

Bootstrap Flux to manage the cluster via this GitHub repository (requires GitHub PAT).
This installs Cilium and all infra automatically.

```bash
flux bootstrap github \
  --owner=agentydragon \
  --repository=cluster \
  --path=k8s \
  --personal \
  --read-write-key
```

This command:
- Installs Flux controllers in `flux-system` namespace
- Creates deploy key in GitHub repository
- Deploys Cilium CNI via GitOps (nodes become Ready)
- Deploys all infrastructure and applications automatically

#### Test
```bash
kubectl get nodes -o wide  # Wait for Flux to deploy Cilium (nodes become Ready)
flux get all               # Check GitOps status
# Note: kubectl automatically uses VIP (10.0.0.20) for HA - no manual --server needed
```

### Step 3: Generate Bootstrap Secrets

Before platform services can deploy, generate bootstrap secrets and commit them to git:

```bash
# Generate bootstrap tokens
for service in "vault:vault:root-token" "authentik:authentik:bootstrap-token"; do
  IFS=':' read -r name ns key <<< "$service"
  openssl rand -hex 32 | \
    kubectl create secret generic ${name}-bootstrap \
    --from-file=${key}=/dev/stdin --namespace=${ns} --dry-run=client -o yaml | \
    kubeseal -o yaml > k8s/infrastructure/platform/${name}/${name}-bootstrap-sealed.yaml
done

# Commit and push to trigger GitOps deployment
git add k8s/infrastructure/platform/*/*-bootstrap-sealed.yaml
git commit -m "feat: add bootstrap secrets for platform services"
git push origin main

# Wait for Flux to reconcile
flux reconcile source git cluster --wait
flux reconcile ks infrastructure-platform --wait
```

#### Test Platform Services
```bash
flux get ks infrastructure-platform  # Check platform services status
kubectl get pods -n vault -n authentik  # Verify platform pods starting
```

### Step 4: External Connectivity via VPS

#### Step 4.1: DNS Delegation

Create NS delegation records in Route 53 to allow Let's Encrypt DNS-01 validation for `test-cluster.agentydragon.com` via PowerDNS on the VPS:
```
Record Name: test-cluster.agentydragon.com
Record Type: NS
Record Value: ns1.agentydragon.com
TTL: 3600
```

#### Step 3.2: PowerDNS configuration

Add `test-cluster.agentydragon.com` domain configuration to `~/code/ducktape/ansible/host_vars/vps/powerdns.yml` with SOA, NS, and wildcard A records pointing to VPS IP.

#### Step 3.3: Let's Encrypt task

Add Let's Encrypt task to VPS playbook, to provision wildcard certificate for `*.test-cluster.agentydragon.com` using DNS-01 challenge via PowerDNS.

#### Step 3.4: NGINX Proxy Site Configuration

Create nginx site template at `~/code/ducktape/ansible/nginx-sites/test-cluster.agentydragon.com.j2` with wildcard proxy configuration for `*.test-cluster.agentydragon.com` → `w0:30443` via Tailscale.

#### Step 3.5: Deploy VPS configuration

```bash
cd ~/code/ducktape/ansible  # From your Ansible directory
ansible-playbook vps.yaml -t powerdns,nginx-sites   # Deploy PowerDNS zones and nginx config
ansible-playbook vps.yaml -t test-cluster-wildcard  # Create Let's Encrypt certificates
```

#### Step 3.6: Test External Connectivity

```bash
dig foo.test-cluster.agentydragon.com  # Should resolve to: 172.235.48.86 (VPS IP)
curl https://test.test-cluster.agentydragon.com/ # Should return HTTP/2 200
```

Cluster should now be fully operational with GitOps-managed infrastructure and external HTTPS connectivity.
