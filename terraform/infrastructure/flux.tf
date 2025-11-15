# Bootstrap Flux GitOps after CNI is ready
# This completes the full cluster setup in a single terraform apply

# Get GitHub PAT from gh CLI
data "external" "github_token" {
  program = ["sh", "-c", "echo '{\"token\": \"'$(gh auth token)'\"}'"]
}

# Bootstrap Flux using native provider
resource "flux_bootstrap_git" "cluster" {
  depends_on = [
    helm_release.cilium_bootstrap,       # Native Helm wait ensures healthy CNI
    kubernetes_secret.sealed_secrets_key # Ensure sealed secrets keypair exists
  ]

  path = "k8s"

  # Components to install
  components_extra = [
    "image-reflector-controller",
    "image-automation-controller"
  ]

  # Network policies for additional security
  network_policy = true
}

