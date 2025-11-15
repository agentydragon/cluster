# Bootstrap Flux GitOps after CNI is ready
# This completes the full cluster setup in a single terraform apply

# Get GitHub PAT from gh CLI
data "external" "github_token" {
  program = ["sh", "-c", "echo '{\"token\": \"'$(gh auth token)'\"}'"]
}

# Bootstrap Flux using the flux provider
resource "null_resource" "flux_bootstrap" {
  depends_on = [
    null_resource.wait_for_nodes_ready,
    kubernetes_secret.sealed_secrets_key
  ]

  provisioner "local-exec" {
    command = <<-EOF
      export GITHUB_TOKEN="${data.external.github_token.result.token}"
      flux bootstrap github \
        --owner=${var.github_owner} \
        --repository=${var.github_repository} \
        --path=k8s \
        --personal \
        --read-write-key
    EOF
  }

  # Trigger re-bootstrap if kubeconfig changes (cluster recreated)
  triggers = {
    kubeconfig_content = local_file.kubeconfig.content
  }
}

# Wait for Flux to be ready
resource "null_resource" "wait_for_flux" {
  depends_on = [null_resource.flux_bootstrap]

  provisioner "local-exec" {
    command = "kubectl wait --for=condition=Ready pods -n flux-system --all --timeout=300s"
  }
}