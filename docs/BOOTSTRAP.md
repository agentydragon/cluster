# Talos Cluster Bootstrap Playbook

Step-by-step instructions for cold-starting the Talos cluster from nothing and managing individual nodes.

## Cold-Start Cluster Deployment

### Prerequisites

- SSH access to `root@atlas` (Proxmox) and `root@agentydragon.com` (Headscale) for auto-provisioning
- `direnv` configured in cluster directory
- VPS with nginx and PowerDNS configured via Ansible
- Access to AWS Route 53 for `agentydragon.com`
- **Stable SealedSecret keypair** stored in libsecret (one-time setup, see below)

### Step 0: One-Time SealedSecret Keypair Setup

**IMPORTANT**: Generate stable keypair ONCE and store in libsecret. Required before first bootstrap:

```bash
# Generate stable keypair (run ONCE per development machine)
openssl genrsa 4096 | secret-tool store service sealed-secrets key private_key
openssl req -new -x509 -key <(secret-tool lookup service sealed-secrets key private_key) \
  -out /tmp/sealed-secrets.crt -days 365 -subj '/CN=sealed-secrets'
secret-tool store service sealed-secrets key public_key < /tmp/sealed-secrets.crt
rm /tmp/sealed-secrets.crt

# Regenerate ALL SealedSecrets with this stable key
kubeseal --cert <(secret-tool lookup service sealed-secrets key public_key) \
  < k8s/storage/proxmox-csi-secret.yaml > k8s/storage/proxmox-csi-sealed.yaml
```

### Step 1: Fully Declarative Deployment

All credentials are auto-provisioned via SSH to `root@atlas` and `root@agentydragon.com`.

```bash
cd terraform/infrastructure
./bootstrap.sh

# Bootstrap script handles validation, terraform apply, and health checks
```

**Prerequisites:** 
- `gh auth login` completed for GitHub access
- Stable SealedSecret keypair in libsecret (Step 0)

This **single command** handles:

- QCOW2 disk image from Talos Image Factory with baked-in static IP configuration
- VM creation with pre-configured networking
- Talos machine configuration application
- Kubernetes cluster initialization and bootstrap
- **Cilium CNI deployment** via Terraform Helm provider (infrastructure layer management)
- **Auto-generated kubeconfig** pointing to VIP for HA kubectl access (see VIP Bootstrap Solution below)
- **Sealed-secrets keypair persistence** via system keyring for turnkey GitOps workflow
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

### Sealed-Secrets Keypair Persistence (Optional Optimization)

The cluster automatically manages sealed-secrets keypair persistence for turnkey GitOps workflows:

- **First deployment**: Sealed-secrets controller generates new keypair, terraform stores it in system keyring
- **Subsequent deployments**: Terraform restores keypair from keyring, all existing sealed secrets work immediately
- **Without persistence**: Each deployment generates new keypair, requiring manual sealed secret regeneration

**No action needed** - this happens automatically during `terraform apply`.

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
