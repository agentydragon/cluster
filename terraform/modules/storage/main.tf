terraform {
  required_providers {
    null = {
      source = "hashicorp/null"
    }
  }
}

# STORAGE MODULE: Proxmox CSI driver and persistent storage
# Manages storage credentials and CSI driver deployment

# Generate Proxmox CSI storage secrets using stable sealed-secrets keypair
resource "null_resource" "proxmox_csi_secret" {
  # Re-run when PVE auth tokens change
  triggers = {
    csi_config_hash = sha256(jsonencode(var.csi_config))
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Create temporary secret file with CSI configuration
      csi_config='${jsonencode(var.csi_config)}'

      # Create kubernetes secret YAML
      cat > /tmp/proxmox-csi-secret.yaml <<EOF
      apiVersion: v1
      kind: Secret
      metadata:
        name: proxmox-csi-plugin
        namespace: csi-proxmox
      type: Opaque
      stringData:
        config.yaml: |
          clusters:
            - url: $(echo "$csi_config" | jq -r .url)
              insecure: $(echo "$csi_config" | jq -r .insecure)
              token_id: $(echo "$csi_config" | jq -r .token_id)
              token_secret: $(echo "$csi_config" | jq -r .token_secret)
              region: $(echo "$csi_config" | jq -r .region)
      EOF

      # Seal the secret using stable keypair from libsecret
      # Write certificate to temporary file (process substitution not supported in all shells)
      secret-tool lookup service sealed-secrets key public_key > /tmp/sealed-secrets-cert.pem
      kubeseal --cert /tmp/sealed-secrets-cert.pem \
        --format=yaml < /tmp/proxmox-csi-secret.yaml > ${path.root}/../../k8s/storage/proxmox-csi-sealed.yaml
      rm /tmp/sealed-secrets-cert.pem

      # Clean up temporary file
      rm /tmp/proxmox-csi-secret.yaml

      echo "Generated sealed secret for Proxmox CSI with stable keypair"
    EOT
  }
}