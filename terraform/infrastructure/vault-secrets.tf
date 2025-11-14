# Sealed-secrets keypair persistence via system keyring
# Extract and store sealed-secrets keypair to survive cluster recreates
resource "null_resource" "store_sealed_secrets_key" {
  provisioner "local-exec" {
    command = <<-EOF
      # Check if sealed-secrets key exists in current cluster
      if kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key=active >/dev/null 2>&1; then
        # Extract the full secret as JSON and store in keyring
        SEALED_SECRET_JSON=$(kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key=active -o json | jq '.items[0]')
        echo "$SEALED_SECRET_JSON" | secret-tool store --label="Sealed Secrets Keypair" service cluster key sealed-secrets-keypair
        echo "Stored sealed-secrets keypair in keyring"
      else
        echo "No sealed-secrets key found in current cluster"
      fi
    EOF
  }

  # Only run when cluster is fully ready
  depends_on = [null_resource.wait_for_nodes_ready]
}

# Deploy sealed-secrets keypair from keyring early in bootstrap (before Flux)
resource "null_resource" "deploy_sealed_secrets_key" {
  provisioner "local-exec" {
    command = <<-EOF
      # Wait for kube-system namespace
      kubectl wait --for=condition=ready namespace/kube-system --timeout=60s

      # Try to retrieve keypair from keyring
      if SEALED_SECRET_JSON=$(secret-tool lookup service cluster key sealed-secrets-keypair 2>/dev/null); then
        echo "Found sealed-secrets keypair in keyring, deploying..."

        # Clean the JSON and apply it directly
        echo "$SEALED_SECRET_JSON" | jq 'del(.metadata.resourceVersion, .metadata.uid, .metadata.creationTimestamp, .metadata.namespace) | .metadata.namespace = "kube-system"' | \
        kubectl apply -f -

        echo "Deployed sealed-secrets keypair from keyring"
      else
        echo "No sealed-secrets keypair found in keyring, controller will generate new one"
      fi

      # Wait for sealed-secrets controller to start
      kubectl wait --for=condition=available deployment/sealed-secrets-controller -n kube-system --timeout=300s
    EOF
  }

  depends_on = [null_resource.wait_for_k8s_api]
}

# No other persistent secrets needed - pre-auth keys generated via SSH