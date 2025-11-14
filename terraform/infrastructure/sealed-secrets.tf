# Sealed Secrets automation for Proxmox CSI
# Waits for sealed-secrets controller, generates sealed secret, commits to git

# Wait for sealed-secrets controller to be ready
resource "null_resource" "wait_for_sealed_secrets" {
  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for sealed-secrets controller..."
      kubectl wait --for=condition=available deployment/sealed-secrets-controller \
        --namespace=kube-system --timeout=300s
      echo "Sealed-secrets controller is ready"
    EOT
  }

  depends_on = [
    null_resource.wait_for_k8s_api,
    helm_release.cilium_bootstrap
  ]
}

# Generate and seal the Proxmox CSI secret
resource "null_resource" "generate_csi_sealed_secret" {
  triggers = {
    csi_token  = data.terraform_remote_state.pve_auth.outputs.csi_token
    api_url    = data.terraform_remote_state.pve_auth.outputs.pve_api_url
    kubeconfig = local_file.kubeconfig.content_sha256
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Generating Proxmox CSI sealed secret..."

      # Extract token parts
      CSI_TOKEN="${data.terraform_remote_state.pve_auth.outputs.csi_token}"
      TOKEN_ID=$(echo "$CSI_TOKEN" | cut -d'=' -f1)
      TOKEN_SECRET=$(echo "$CSI_TOKEN" | cut -d'=' -f2)

      # Create config YAML
      cat > /tmp/csi-config.yaml <<EOF
      clusters:
      - url: ${data.terraform_remote_state.pve_auth.outputs.pve_api_url}
        insecure: true
        token_id: "$TOKEN_ID"
        token_secret: "$TOKEN_SECRET"
        region: default
      EOF

      # Generate sealed secret
      kubectl create secret generic proxmox-csi-plugin \
        --namespace=csi-proxmox \
        --from-file=config.yaml=/tmp/csi-config.yaml \
        --dry-run=client -o yaml | \
      kubeseal -o yaml > k8s/storage/proxmox-csi-sealed.yaml

      # Clean up temp file
      rm -f /tmp/csi-config.yaml

      echo "Proxmox CSI sealed secret generated"
    EOT
  }

  depends_on = [null_resource.wait_for_sealed_secrets]
}

# Commit and push the sealed secret to trigger Flux reconciliation
resource "null_resource" "commit_csi_sealed_secret" {
  triggers = {
    sealed_secret_content = null_resource.generate_csi_sealed_secret.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Committing Proxmox CSI sealed secret to git..."

      # Stage and commit the sealed secret
      git add k8s/storage/proxmox-csi-sealed.yaml
      git commit -m "feat: update Proxmox CSI sealed secret with new credentials

      - Auto-generated sealed secret from terraform infrastructure
      - Uses credentials from SSH-provisioned PVE tokens
      - Enables storage layer GitOps deployment

      🤖 Generated with [Claude Code](https://claude.ai/code)

      Co-Authored-By: Claude <noreply@anthropic.com>" || echo "No changes to commit"

      # Push to trigger Flux reconciliation
      git push origin main

      echo "Sealed secret committed and pushed"
    EOT
  }

  depends_on = [null_resource.generate_csi_sealed_secret]
}

# Force Flux to reconcile the storage kustomization
resource "null_resource" "flux_reconcile_storage" {
  triggers = {
    sealed_secret_commit = null_resource.commit_csi_sealed_secret.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Triggering Flux reconciliation..."

      # Reconcile source (git repository)
      flux reconcile source git flux-system --timeout=60s

      # Reconcile storage kustomization
      flux reconcile kustomization storage --timeout=60s

      echo "Flux reconciliation triggered"
    EOT
  }

  depends_on = [
    null_resource.commit_csi_sealed_secret,
    null_resource.wait_for_flux
  ]
}