# Cilium CNI deployment via Terraform Helm provider
# Infrastructure layer management - prevents GitOps circular dependencies

# Add Cilium helm repository
resource "null_resource" "add_cilium_repo" {
  provisioner "local-exec" {
    command = "helm repo add cilium https://helm.cilium.io/ && helm repo update"
  }
  depends_on = [null_resource.wait_for_k8s_api]
}

resource "helm_release" "cilium_bootstrap" {
  name             = "cilium"
  repository       = "cilium" # Use repo name instead of URL
  chart            = "cilium"
  version          = "1.16.5"
  namespace        = "kube-system"
  create_namespace = true

  values = [
    file("${path.module}/cilium/values.yaml")
  ]

  # Reliability improvements
  wait         = true
  timeout      = 600
  max_history  = 3
  force_update = false
  reset_values = false

  # Prevent accidental networking breakage
  lifecycle {
    ignore_changes = [
      version, # Prevent automatic upgrades
      values   # Prevent config drift issues
    ]
  }

  depends_on = [
    null_resource.add_cilium_repo
  ]
}

# Wait for Kubernetes API to be accessible before installing Cilium
resource "null_resource" "wait_for_k8s_api" {
  depends_on = [
    local_file.kubeconfig,
    module.nodes
  ]

  provisioner "local-exec" {
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

# Wait for all expected nodes to join and become Ready after CNI installation
resource "null_resource" "wait_for_nodes_ready" {
  depends_on = [helm_release.cilium_bootstrap]

  provisioner "local-exec" {
    command = <<-EOF
      echo "Waiting for all expected nodes to become Ready..."

      # Wait for all expected nodes by name (dynamically generated)
      kubectl wait --for=condition=Ready ${join(" ", [for node_name, _ in local.nodes : "node/${node_name}"])} --timeout=600s

      echo "All ${var.controller_count + var.worker_count} nodes are Ready"
    EOF
  }
}