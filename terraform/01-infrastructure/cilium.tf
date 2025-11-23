# Cilium CNI deployment via Terraform Helm provider
# Infrastructure layer management - prevents GitOps circular dependencies

# Add Cilium helm repository
resource "null_resource" "add_cilium_repo" {
  provisioner "local-exec" {
    command = "helm repo add cilium https://helm.cilium.io/ && helm repo update"
  }
  depends_on = [null_resource.wait_for_k8s_api, local_file.kubeconfig]
}

resource "helm_release" "cilium_bootstrap" {
  name             = "cilium"
  repository       = "cilium" # Use repo name instead of URL
  chart            = "cilium"
  version          = "1.16.5"
  namespace        = "kube-system"
  create_namespace = true

  values = [
    file("../modules/infrastructure/cilium/values.yaml")
  ]

  # Native Helm provider reliability and health checking
  wait            = true
  wait_for_jobs   = true
  atomic          = true # Rollback on failure
  cleanup_on_fail = true # Clean up resources on failure
  timeout         = 600
  max_history     = 3
  force_update    = false
  reset_values    = false

  # Prevent accidental networking breakage
  lifecycle {
    ignore_changes = [
      version, # Prevent automatic upgrades
      values   # Prevent config drift issues
    ]
  }

  # Clean up PVCs before Cilium is destroyed (while cluster is still accessible)
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "🧹 Cleaning up orphaned PVCs before cluster teardown..."

      # Get all PVCs with proxmox-csi-retain storage class
      PVCS=$(kubectl --kubeconfig="${path.module}/kubeconfig" get pvc -A \
        -o jsonpath='{range .items[?(@.spec.storageClassName=="proxmox-csi-retain")]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' 2>/dev/null || true)

      if [ -n "$PVCS" ]; then
        echo "📋 Found PVCs to delete:"
        echo "$PVCS"
        echo "$PVCS" | while IFS='/' read -r ns name; do
          [ -n "$ns" ] && [ -n "$name" ] && kubectl --kubeconfig="${path.module}/kubeconfig" delete pvc "$name" -n "$ns" --ignore-not-found=true --wait=false
        done
        echo "✅ PVC cleanup initiated"
      else
        echo "ℹ️  No PVCs found to clean up"
      fi
    EOT
  }

  depends_on = [
    null_resource.wait_for_k8s_api, # Wait for k8s API readiness via bash check
    null_resource.add_cilium_repo,
    local_file.kubeconfig
  ]
}

# Wait for Kubernetes API to be accessible before installing Cilium
resource "null_resource" "wait_for_k8s_api" {
  depends_on = [
    module.infrastructure,
    local_file.kubeconfig
  ]

  provisioner "local-exec" {
    environment = {
      KUBECONFIG = local_file.kubeconfig.filename
    }
    command = <<-EOF
      echo "Waiting for Kubernetes API to be ready..."
      i=1
      while [ $i -le 60 ]; do
        if kubectl get nodes --request-timeout=10s >/dev/null 2>&1 && \
           kubectl get serviceaccount default -n default --request-timeout=10s >/dev/null 2>&1 && \
           kubectl auth can-i create pods --request-timeout=10s >/dev/null 2>&1; then
          echo "Kubernetes API is fully ready for workloads!"
          exit 0
        fi
        echo "Attempt $i/60: Waiting for API readiness..."
        sleep 10
        i=$((i + 1))
      done
      echo "Kubernetes API failed to become ready after 10 minutes"
      exit 1
    EOF
  }
}

