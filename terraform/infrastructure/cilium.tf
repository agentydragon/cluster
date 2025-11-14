# Cilium CNI deployment via Terraform Helm provider
# Infrastructure layer management - prevents GitOps circular dependencies
resource "helm_release" "cilium" {
  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = "1.16.5"
  namespace  = "kube-system"

  values = [
    file("${path.module}/cilium/values.yaml")
  ]

  # Prevent accidental networking breakage
  lifecycle {
    ignore_changes = [
      version, # Prevent automatic upgrades
      values   # Prevent config drift issues
    ]
  }

  depends_on = [
    null_resource.wait_for_k8s_api
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
        if kubectl get nodes --request-timeout=10s >/dev/null 2>&1; then
          echo "Kubernetes API is ready!"
          exit 0
        fi
        echo "Attempt $i/60: Waiting for API..."
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
  depends_on = [helm_release.cilium]

  provisioner "local-exec" {
    command = <<-EOF
      echo "Waiting for all expected nodes to become Ready..."

      # Wait for all expected nodes by name (dynamically generated)
      kubectl wait --for=condition=Ready ${join(" ", [for node_name, _ in local.nodes : "node/${node_name}"])} --timeout=600s

      echo "All ${var.controller_count + var.worker_count} nodes are Ready"
    EOF
  }
}