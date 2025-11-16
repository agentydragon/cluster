# Automatic sealing of secrets using the terraform-generated keypair
# This ensures all secrets are sealed with the correct keypair

locals {
  # Define secrets that need to be sealed
  secrets_to_seal = {
    "proxmox-csi" = {
      namespace = "csi-proxmox"
      name      = "proxmox-csi-plugin"
      content = yamlencode({
        apiVersion = "v1"
        kind       = "Secret"
        metadata = {
          name      = "proxmox-csi-plugin"
          namespace = "csi-proxmox"
        }
        type = "Opaque"
        stringData = {
          "config.yaml" = jsonencode({
            clusters = [data.terraform_remote_state.pve_auth.outputs.csi_config]
          })
        }
      })
      output_path = "${path.module}/../../k8s/storage/proxmox-csi-sealed.yaml"
    }
  }
}

# Seal each secret with kubeseal
resource "null_resource" "seal_secrets" {
  for_each = local.secrets_to_seal

  triggers = {
    # Re-seal when the certificate changes or content changes
    cert_hash    = sha256(local.sealed_secrets_cert_pem)
    content_hash = sha256(each.value.content)
  }

  provisioner "local-exec" {
    command = <<-EOF
      # Write the certificate to a temp file
      echo '${local.sealed_secrets_cert_pem}' > /tmp/seal-cert-${each.key}.pem

      # Write the secret to a temp file
      cat > /tmp/secret-${each.key}.yaml <<'SECRET_EOF'
      ${each.value.content}
      SECRET_EOF

      # Seal the secret
      kubeseal --cert /tmp/seal-cert-${each.key}.pem \
               --format yaml \
               < /tmp/secret-${each.key}.yaml \
               > ${each.value.output_path}

      # Clean up temp files
      rm /tmp/seal-cert-${each.key}.pem /tmp/secret-${each.key}.yaml

      echo "Sealed secret for ${each.key} saved to ${each.value.output_path}"
    EOF
  }

  depends_on = [
    data.external.sealed_secrets_keypair
  ]
}

# Commit the sealed secrets if they changed
resource "null_resource" "commit_sealed_secrets" {
  triggers = {
    # Re-run when any secret is resealed
    seal_hash = sha256(jsonencode([for k, v in local.secrets_to_seal : null_resource.seal_secrets[k].id]))
  }

  provisioner "local-exec" {
    command = <<-EOF
      cd ${path.module}/../..

      # Check if there are changes to sealed secrets
      if git diff --quiet k8s/**/*-sealed.yaml 2>/dev/null; then
        echo "No changes to sealed secrets"
      else
        # Add and commit the changes
        git add k8s/**/*-sealed.yaml
        git commit -m "chore: auto-seal secrets with terraform-generated keypair

Terraform automatically resealed secrets with the stable keypair.

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>" || true
        echo "Committed updated sealed secrets"
      fi
    EOF
  }

  depends_on = [
    null_resource.seal_secrets
  ]
}

