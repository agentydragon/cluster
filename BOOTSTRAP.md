# Talos Cluster Bootstrap Playbook

This document provides step-by-step instructions for cold-starting the Talos cluster from nothing and managing individual nodes.

## Cold-Start Cluster Deployment (From Nothing)

### Prerequisites
- Proxmox host (`atlas`) accessible via SSH
- Ansible vault configured with API tokens
- `direnv` configured in cluster directory

### Step 1: Fully Declarative Deployment
```bash
cd /home/agentydragon/code/cluster/terraform

# ✅ SINGLE COMMAND DEPLOYMENT - Everything automated!
./tf.sh apply

# This command now handles:
# - QCOW2 disk image download with static IP configuration
# - VM creation with pre-configured networking
# - Talos machine configuration application
# - Cluster bootstrap (automatic)
# - Kubernetes cluster initialization
```

### Step 2: Verify Deployment Success
```bash
# All VMs should be running with correct static IPs
ping 10.0.0.11  # c0 (controller)
ping 10.0.0.12  # c1 (controller)
ping 10.0.0.13  # c2 (controller) 
ping 10.0.0.21  # w0 (worker)
ping 10.0.0.22  # w1 (worker)

# ✅ VIP should be active immediately after terraform completes
ping 10.0.0.20  # VIP (load balancer)
```

### Step 3: Install CNI (Required for Node Ready Status)
```bash
# Navigate to cluster root (KUBECONFIG automatically set via .envrc)
cd /home/agentydragon/code/cluster

# Add Cilium repository
helm repo add cilium https://helm.cilium.io/
helm repo update

# Install Cilium with Talos-specific configuration
helm install cilium cilium/cilium --namespace kube-system --version 1.16.5 \
  --set cluster.name=talos-cluster \
  --set cluster.id=1 \
  --set k8sServiceHost=10.0.0.11 \
  --set k8sServicePort=6443 \
  --set ipam.mode=kubernetes \
  --set securityContext.capabilities.ciliumAgent='{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}' \
  --set securityContext.capabilities.cleanCiliumState='{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}' \
  --set cgroup.hostRoot=/sys/fs/cgroup \
  --set cgroup.autoMount.enabled=false
```

### Step 4: Verify Full Cluster Health
```bash
# ✅ All nodes should show Ready status
kubectl get nodes -o wide

# ✅ Test VIP functionality
kubectl --server=https://10.0.0.20:6443 get nodes

# ✅ Verify Cilium pods are running
kubectl get pods -n kube-system -l k8s-app=cilium
```

## Adding New Nodes

### Controller Node
```bash
cd /home/agentydragon/code/cluster/terraform

# Update terraform.tfvars:
# controller_count = 4  # or desired count

# Apply changes
./tf.sh apply

# New controller will automatically join the cluster
# Verify with talosctl get members
```

### Worker Node  
```bash
cd /home/agentydragon/code/cluster/terraform

# Update terraform.tfvars:
# worker_count = 3  # or desired count

# Apply changes
./tf.sh apply

# New worker will automatically join
# Verify with kubectl get nodes
```

## Node Maintenance

### Restart Single Node
```bash
# Gracefully restart a node (example: controller-1)
talosctl \
  --talosconfig /home/agentydragon/code/cluster/terraform/talosconfig.yml \
  --endpoints 10.0.0.11 \
  --nodes 10.0.0.11 \
  reboot

# Or force restart via Proxmox
ssh root@atlas 'qm reboot 106'
```

### Remove Node
```bash
# From Kubernetes perspective
kubectl delete node talos-controller-1

# Update terraform.tfvars to reduce count, then:
./tf.sh apply
```

## VM Console Management

### Take VM Screenshots

See `~/.claude/skills/proxmox-vm-screenshot/vm-screenshot.sh`

### Direct VM Console Access
```bash
# Interactive console access (from Proxmox host)
ssh root@atlas
qm terminal 106  # controller-1
```

## Troubleshooting Common Issues

### Bootstrap Hanging
**Symptoms**: `talosctl bootstrap` times out or hangs
**Solution**: Verify cluster_endpoint points to first controller IP, not VIP:
```hcl
cluster_endpoint = "https://10.0.0.11:6443"  # NOT 10.0.0.20:6443
```

### Static IP Not Working
**Symptoms**: VMs get DHCP addresses instead of static IPs
**Solution**: Check META key 10 configuration in module and restart VMs

### API Not Responding
**Symptoms**: `connection refused` on port 50000
**Solution**: Wait longer for boot, check console via screenshots

### Network Connectivity Issues
**Symptoms**: Cannot reach VMs on expected IPs
**Solution**: Verify network configuration in terraform.tfvars matches infrastructure

## Key File Locations

- **Terraform configs**: `/home/agentydragon/code/cluster/terraform/`
- **Talos config**: `terraform/talosconfig.yml` (generated, gitignored)
- **Kube config**: `terraform/kubeconfig` (generated, gitignored)
- **Environment**: `/home/agentydragon/code/cluster/.envrc` (direnv)

## Node IP Assignments

| Node | VM ID | IP Address | Role |
|------|-------|------------|------|
| controller-1 | 106 | 10.0.0.11 | Controller |
| controller-2 | 107 | 10.0.0.12 | Controller |
| controller-3 | 108 | 10.0.0.13 | Controller |
| worker-1 | 109 | 10.0.0.21 | Worker |
| worker-2 | 110 | 10.0.0.22 | Worker |
| **VIP** | - | 10.0.0.20 | Load Balancer |

## Next Steps After Bootstrap

1. **✅ CNI Installed**: Cilium v1.16.5 providing networking and security
2. **GitOps Migration**: Consider migrating Cilium from Helm to Flux for declarative management
3. **Install Platform Services**: Vault, Authentik, Harbor, Gitea via GitOps
4. **Configure Backup**: Set up etcd backup and restore procedures
5. **Monitor Setup**: Deploy monitoring and observability stack
6. **Security Hardening**: Apply network policies via Cilium

## Step 5: Set Up GitOps with Flux (Recommended)

Establish declarative cluster management using this GitHub repository:

```bash
cd /home/agentydragon/code/cluster

# Bootstrap Flux using this repository  
flux bootstrap github \
  --owner=agentydragon \
  --repository=cluster \
  --path=flux-system \
  --personal \
  --read-write-key

# This will:
# - Install Flux controllers in the cluster
# - Create flux-system/ directory in this repo
# - Set up GitOps workflow for future deployments
```

### Migrate Cilium to GitOps (Optional)
```bash
# Export current Cilium values for GitOps
helm get values cilium -n kube-system > apps/cilium/values.yaml

# Create HelmRelease manifest (see PLAN.md for details)
# Commit and push - Flux will adopt existing Helm installation
```

### Future Deployments
After Flux setup, all cluster changes go through Git:
```bash
# Add new applications via Git workflow
git add apps/monitoring/
git commit -m "Add Prometheus monitoring stack"  
git push
# Flux automatically deploys within ~1 minute
```
