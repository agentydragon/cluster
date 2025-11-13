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

# After terraform completes, run the Stage 1 health check to verify everything is working:
./stage1-health-check.py
```

**Prerequisites:** Ensure `gh auth login` is completed for GitHub access.

This **single command** handles:
- QCOW2 disk image from Talos Image Factory with baked-in static IP configuration
- VM creation with pre-configured networking
- Talos machine configuration application
- Kubernetes cluster initialization and bootstrap
- **Cilium CNI bootstrap** to enable pod scheduling (solves Flux chicken-and-egg problem)
- **Auto-generated kubeconfig** pointing to VIP for HA kubectl access
- **Nodes become Ready** after CNI installation
- **Flux GitOps bootstrap** using `gh auth token` for GitHub PAT
- **Deploy key creation** in GitHub repository
- **Seamless Flux takeover** of Cilium management via GitOps
- **Infrastructure deployment** starts automatically (platform services require bootstrap secrets)

#### Test
```bash
kubectl get nodes -o wide  # Nodes should be Ready with CNI installed
flux get all               # Check GitOps status - should show healthy reconciliations
kubectl get pods -A        # All system pods should be running
# Note: kubectl automatically uses VIP (10.0.0.20) for HA - no manual --server needed
```

### Step 2: Generate Bootstrap Secrets

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

#### Test
```bash
flux get ks infrastructure-platform  # Check platform services status
kubectl get pods -n vault -n authentik  # Verify platform pods starting
```

### Step 3: External Connectivity via VPS

#### Step 3.1: DNS Delegation

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

Cluster should now be operational with GitOps and external HTTPS connectivity.
