# LAYER 2: SERVICES
# Service deployment via GitOps - requires Layer 1 to be complete

# Static provider configuration - Layer 1 writes kubeconfig to known location
provider "kubernetes" {
  config_path = "../01-infrastructure/kubeconfig"
}

provider "helm" {
  kubernetes {
    config_path = "../01-infrastructure/kubeconfig"
  }
}

provider "flux" {
  kubernetes = {
    config_path = "../01-infrastructure/kubeconfig"
  }
  git = {
    url = "ssh://git@github.com/agentydragon/cluster.git"
    ssh = {
      username    = "git"
      private_key = file("~/.ssh/id_ed25519")
    }
  }
}

# Vault secrets managed by tofu-controller after Flux deploys Vault
# See: terraform/gitops/secrets/ for Vault secret management

# Test Kubernetes connectivity
resource "kubernetes_namespace" "test" {
  metadata {
    name = "test-namespace"
  }
}

# FLUX BOOTSTRAP: Initialize GitOps engine
resource "flux_bootstrap_git" "cluster" {
  path = "k8s"
  depends_on = [
    kubernetes_namespace.test,
  ]
}

# NOTE: Service configuration moved to Layer 3 after services are deployed
# Layer 2 only deploys services via Flux - configuration happens in Layer 3