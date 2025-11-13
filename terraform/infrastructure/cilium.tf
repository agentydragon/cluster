# Bootstrap Cilium CNI to break chicken-and-egg problem
# Flux needs CNI to schedule pods, but CNI comes from Flux
# This manual installation allows Flux to start, then Flux takes over Cilium management

# Read the existing HelmRelease YAML to extract values
data "local_file" "cilium_helmrelease" {
  filename = "${path.root}/../../k8s/infrastructure/networking/cilium/helmrelease.yaml"
}

locals {
  # Parse the HelmRelease YAML and extract values
  cilium_helmrelease = yamldecode(data.local_file.cilium_helmrelease.content)
  cilium_values = merge(
    local.cilium_helmrelease.spec.values,
    {
      # Override with dynamic terraform values
      k8sServiceHost = var.cluster_vip
    }
  )
}

resource "helm_release" "cilium_bootstrap" {
  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = local.cilium_helmrelease.spec.chart.spec.version
  namespace  = "kube-system"

  # Use the exact same values from the HelmRelease YAML
  values = [yamlencode(local.cilium_values)]

  # Wait for cluster to be ready
  depends_on = [
    null_resource.wait_for_k8s_api
  ]

  # Allow Flux to take over management later
  lifecycle {
    ignore_changes = [
      version,
      values
    ]
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
resource "time_sleep" "wait_for_cni" {
  depends_on      = [helm_release.cilium_bootstrap]
  create_duration = "30s" # Give CNI time to start
}

# Use kubectl wait which has proper retry and timeout logic
resource "null_resource" "wait_for_nodes_ready" {
  depends_on = [time_sleep.wait_for_cni]

  provisioner "local-exec" {
    command = "kubectl wait --for=condition=Ready nodes --all --timeout=300s"
  }
}