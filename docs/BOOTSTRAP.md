# Talos Cluster Bootstrap Playbook

Step-by-step instructions for cold-starting the Talos cluster from nothing and managing individual nodes.

## Cold-Start Cluster Deployment

### Prerequisites

- Proxmox host (`atlas`) accessible via SSH
- Proxmox credentials configured in libsecret keyring (see [Credential Setup](#credential-setup))
- SSH access to Headscale server (`root@agentydragon.com`) for pre-auth key generation
- `direnv` configured in cluster directory
- VPS with nginx and PowerDNS configured via Ansible
- Access to AWS Route 53 for `agentydragon.com`

## Credential Setup

The deployment uses SSH-based auto-provisioning for both Proxmox and Headscale credentials.
You only need to store the root credentials in your system keyring.

### Step 0.1: Store Root Credentials in libsecret Keyring

Store the root credentials as JSON in your system keyring:

```bash
# Store Proxmox root token for auto-provisioning
secret-tool store generic-secret name "proxmox-terraform-token" \
  --label="Proxmox Root API Token"
# When prompted, enter JSON: {"token":"root@pam!your-root-token=your-secret-here"}

# Store Proxmox root token for CSI (same as above for now)
secret-tool store generic-secret name "proxmox-csi-token" \
  --label="Proxmox Root API Token"
# When prompted, enter JSON: {"token":"root@pam!your-root-token=your-secret-here"}
```

**Verify credentials are stored:**

```bash
secret-tool lookup generic-secret name "proxmox-terraform-token"
secret-tool lookup generic-secret name "proxmox-csi-token"
```

### Step 0.2: Initialize Credential Module

Initialize and apply the credential module:

```bash
cd terraform/pve-auth
terraform init
terraform apply
```

### Step 1: Fully Declarative Deployment

```bash
cd terraform/infrastructure
terraform apply

# After terraform completes, run the Stage 1 health check to verify everything is working:
./cluster-health-check.py
```

**Prerequisites:** Ensure `gh auth login` is completed for GitHub access.

This **single command** handles:

- QCOW2 disk image from Talos Image Factory with baked-in static IP configuration
- VM creation with pre-configured networking
- Talos machine configuration application
- Kubernetes cluster initialization and bootstrap
- **Cilium CNI deployment** via Terraform Helm provider (infrastructure layer management)
- **Auto-generated kubeconfig** pointing to VIP for HA kubectl access (see VIP Bootstrap Solution below)
- **Nodes become Ready** after CNI installation
- **Flux GitOps bootstrap** using `gh auth token` for GitHub PAT
- **Deploy key creation** in GitHub repository
- **Application deployment** starts automatically via Flux (platform services require bootstrap secrets)

**CNI Architecture**: Cilium is managed by Terraform at the infrastructure layer, NOT by Flux. This prevents circular
dependencies where GitOps tools would manage their own networking infrastructure.

#### Test

```bash
kubectl get nodes -o wide  # Nodes should be Ready with CNI installed
flux get all               # Check GitOps status - should show healthy reconciliations
kubectl get pods -A        # All system pods should be running
# Note: kubectl automatically uses VIP (10.0.0.20) for HA - no manual --server needed
```

### Step 2: Storage Configuration

Configure storage backend after sealed-secrets controller is deployed:

```bash
# Wait for sealed-secrets controller to be ready
kubectl wait --for=condition=Available deployment/sealed-secrets-controller -n kube-system --timeout=300s

# Generate Proxmox CSI sealed secret using storage terraform
cd terraform/storage
terraform init
terraform apply

# Commit the generated sealed secret
git add ../../k8s/storage/proxmox-csi-sealed.yaml
git commit -m "feat: add Proxmox CSI sealed secret"
git push origin main

# Wait for storage to be ready
flux reconcile source git cluster --wait
flux reconcile ks infrastructure-storage --wait
```

#### Storage Verification

```bash
kubectl get storageclass                    # Should show proxmox-csi (default)
kubectl get pods -n csi-proxmox            # CSI controller and node pods running
kubectl get csinode                        # Verify CSI driver registered
```

### Step 3: Generate Bootstrap Secrets

After storage is ready, generate bootstrap secrets for platform services:

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

#### Verification

```bash
flux get ks infrastructure-platform  # Check platform services status
kubectl get pods -n vault -n authentik  # Verify platform pods starting
```

### Step 4: External Connectivity via DNS Delegation

#### Step 4.1: DNS Delegation Setup

Create NS delegation in Route 53 for `test-cluster.agentydragon.com` to VPS PowerDNS, then delegate to cluster.

#### Step 4.2: VPS Configuration Updates

Update `~/code/ducktape` repository configurations:

- **PowerDNS**: Add delegation in `ansible/host_vars/vps/powerdns.yml` to cluster PowerDNS VIP (10.0.3.3)
- **NGINX**: Update `ansible/nginx-sites/test-cluster.agentydragon.com.j2` for SNI passthrough to cluster ingress VIP (10.0.3.2:443)

#### Step 4.3: Deploy VPS Configuration

```bash
cd ~/code/ducktape/ansible
ansible-playbook vps.yaml -t powerdns,nginx-sites
```

#### Step 4.4: Wait for In-Cluster PowerDNS

Monitor Flux deployment of platform services:

```bash
flux get ks infrastructure-platform  # Wait for platform services
kubectl get pods -n dns-system       # Verify PowerDNS pod running
kubectl get svc powerdns-external    # Should show LoadBalancer IP 10.0.3.3
```

#### Step 4.5: Test DNS Delegation Chain

```bash
# Test VPS → cluster DNS delegation
dig @ns1.agentydragon.com test-cluster.agentydragon.com NS
# Test cluster PowerDNS directly
dig @10.0.3.3 test.test-cluster.agentydragon.com
# Test SNI passthrough (port 8443)
curl https://test.test-cluster.agentydragon.com:8443/
```

Cluster should now be operational with GitOps and external HTTPS connectivity.

## VIP Bootstrap Solution

The cluster solves the VIP chicken-and-egg problem (can't bootstrap with VIP that doesn't exist yet) through terraform:

1. Bootstrap uses direct controller IP (`10.0.1.1:6443`)
2. Generated kubeconfig uses VIP (`10.0.3.1:6443`) for operations

Users only see the final VIP-based kubeconfig - the bootstrap complexity is internal to terraform.
