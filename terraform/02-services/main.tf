# LAYER 2: SERVICES
# Service deployment via GitOps - no external service APIs
# Includes: Authentik, PowerDNS, Harbor, Gitea, Matrix via Flux

# Configure providers using infrastructure from layer 1
provider "kubernetes" {
  config_path = data.terraform_remote_state.infrastructure.outputs.kubeconfig
}

provider "helm" {
  kubernetes {
    config_path = data.terraform_remote_state.infrastructure.outputs.kubeconfig
  }
}

# GITOPS MODULE: SSO services deployment
# Deploys services via Flux but does not configure them via APIs
module "gitops" {
  source = "../modules/gitops"

  cluster_domain = data.terraform_remote_state.infrastructure.outputs.cluster_domain
}