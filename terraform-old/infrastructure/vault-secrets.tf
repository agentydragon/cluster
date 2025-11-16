# NOTE: Old keypair extraction/storage approach removed
# The new approach generates keypair directly in terraform (see sealed-secrets-keypair.tf)

# Wait for sealed-secrets controller to be ready after Flux deploys it
resource "null_resource" "wait_for_sealed_secrets" {
  provisioner "local-exec" {
    command = <<-EOF
      # Wait for sealed-secrets controller to be deployed by Flux
      kubectl wait --for=condition=available deployment/sealed-secrets-controller -n kube-system --timeout=300s
      echo "Sealed-secrets controller is ready"
    EOF
  }

  depends_on = [flux_bootstrap_git.cluster]
}

# No other persistent secrets needed - pre-auth keys generated via SSH