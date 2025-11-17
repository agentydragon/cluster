# LAYER 2: SERVICES
# Service deployment via GitOps - no external service APIs
# Includes: Authentik, PowerDNS, Harbor, Gitea, Matrix via Flux

# Configure providers using infrastructure from layer 1
provider "kubernetes" {
  host                   = data.terraform_remote_state.infrastructure.outputs.cluster_endpoint
  client_certificate     = base64decode(data.terraform_remote_state.infrastructure.outputs.kubeconfig_data.client_certificate)
  client_key             = base64decode(data.terraform_remote_state.infrastructure.outputs.kubeconfig_data.client_key)
  cluster_ca_certificate = base64decode(data.terraform_remote_state.infrastructure.outputs.kubeconfig_data.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = data.terraform_remote_state.infrastructure.outputs.cluster_endpoint
    client_certificate     = base64decode(data.terraform_remote_state.infrastructure.outputs.kubeconfig_data.client_certificate)
    client_key             = base64decode(data.terraform_remote_state.infrastructure.outputs.kubeconfig_data.client_key)
    cluster_ca_certificate = base64decode(data.terraform_remote_state.infrastructure.outputs.kubeconfig_data.cluster_ca_certificate)
  }
}

provider "flux" {
  kubernetes = {
    host                   = data.terraform_remote_state.infrastructure.outputs.cluster_endpoint
    client_certificate     = base64decode(data.terraform_remote_state.infrastructure.outputs.kubeconfig_data.client_certificate)
    client_key             = base64decode(data.terraform_remote_state.infrastructure.outputs.kubeconfig_data.client_key)
    cluster_ca_certificate = base64decode(data.terraform_remote_state.infrastructure.outputs.kubeconfig_data.cluster_ca_certificate)
  }
  git = {
    url = "ssh://git@github.com/agentydragon/cluster.git"
    ssh = {
      username    = "git"
      private_key = file("~/.ssh/id_ed25519")
    }
  }
}

# FLUX BOOTSTRAP: Initialize GitOps engine
resource "flux_bootstrap_git" "cluster" {
  path = "k8s"

  # Pin Flux version to prevent drift
  version = "v2.7.3"

  # Use embedded manifests to avoid GitOps version mismatches
  embedded_manifests = true

  # Components to install
  components_extra = [
    "image-reflector-controller",
    "image-automation-controller"
  ]

  # Network policies for additional security
  network_policy = true
}

# GITOPS MODULE: SSO services deployment
# Deploys services via Flux but does not configure them via APIs
module "gitops" {
  source     = "../modules/gitops"
  depends_on = [flux_bootstrap_git.cluster]

  cluster_domain = data.terraform_remote_state.infrastructure.outputs.cluster_domain
}