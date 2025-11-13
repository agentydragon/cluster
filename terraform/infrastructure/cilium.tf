# Bootstrap Cilium CNI only to break chicken-and-egg problem
# Flux will manage everything else through HelmReleases
resource "helm_release" "cilium_bootstrap" {
  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = "1.16.5"
  namespace  = "kube-system"

  # Use shared bootstrap config - SSOT with Flux
  values = [file("${path.module}/../../k8s/platform/cilium-bootstrap-values.yaml")]

  # Wait for cluster to be ready
  depends_on = [
    null_resource.wait_for_k8s_api
  ]

  # Allow Flux to take over management
  lifecycle {
    ignore_changes = [values, version]
  }
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
      while [ $i -le 30 ]; do
        if kubectl get nodes --request-timeout=10s >/dev/null 2>&1; then
          echo "Kubernetes API is ready!"
          exit 0
        fi
        echo "Attempt $i/30: Waiting for API..."
        sleep 10
        i=$((i + 1))
      done
      echo "Kubernetes API failed to become ready after 5 minutes"
      exit 1
    EOF
  }
}

# Wait for nodes to become Ready after CNI installation
resource "null_resource" "wait_for_nodes_ready" {
  depends_on = [helm_release.cilium_bootstrap]

  provisioner "local-exec" {
    command = "kubectl wait --for=condition=Ready nodes --all --timeout=300s"
  }
}