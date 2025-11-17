# LAYER 0: PERSISTENT AUTH
# Persistent authentication credentials that survive VM lifecycle
# Includes: CSI tokens, sealed secrets keypair, persistent auth storage

terraform {
  required_providers {
    external = {
      source = "hashicorp/external"
    }
    null = {
      source = "hashicorp/null"
    }
  }
}

# DRY configuration for persistent auth
locals {
  proxmox_host = "root@${var.proxmox_host}"

  # Only CSI token - terraform token is ephemeral per VM lifecycle
  pve_persistent_users = {
    csi = {
      name    = "kubernetes-csi@pve"
      comment = "Kubernetes CSI driver service account (persistent)"
      role    = "CSI"
      privs   = "VM.Audit,VM.Config.Disk,Datastore.Allocate,Datastore.AllocateSpace,Datastore.Audit"
      token   = "csi"
    }
  }
}

# Auto-provision persistent Proxmox users and tokens via SSH
data "external" "pve_persistent_tokens" {
  for_each = local.pve_persistent_users

  program = ["bash", "-c", <<-EOT
    token_json=$(ssh ${local.proxmox_host} '
      # Create user if not exists
      pveum user add ${each.value.name} --comment "${each.value.comment}" 2>/dev/null || true

      # Create role if not exists
      pveum role add ${each.value.role} -privs "${each.value.privs}" 2>/dev/null || true

      # Set ACL permissions
      pveum aclmod / -user ${each.value.name} -role ${each.value.role}

      # Create/recreate API token with JSON output
      pveum user token delete ${each.value.name} ${each.value.token} 2>/dev/null || true
      pveum user token add ${each.value.name} ${each.value.token} --privsep 0 --output-format json
    ')
    # Extract the token value and create complete CSI configuration
    token_value=$(echo "$token_json" | jq -r '.value')
    token_id="${each.value.name}!${each.value.token}"

    # Create CSI config JSON and properly escape it as a string
    csi_config_json=$(cat <<JSON
{"url":"https://${var.proxmox_api_host}/api2/json","insecure":false,"token_id":"$token_id","token_secret":"$token_value","region":"cluster","token":"$token_id=$token_value"}
JSON
)
    # Output for terraform external - wrap JSON as escaped string
    printf '{"config_json":"%s"}' "$(echo "$csi_config_json" | sed 's/"/\\"/g')"
  EOT
  ]
}

# Sealed Secrets Keypair Generation with LibSecret Storage
# Stores keypair in system keyring for true persistence across destroy/apply cycles

# STRICT RETRIEVAL: Require stable keypair to exist in libsecret
data "external" "sealed_secrets_keypair" {
  program = ["bash", "-c", <<-EOF
    set -e

    # Retrieve private key - MUST exist
    if ! private_key=$(secret-tool lookup service sealed-secrets key private_key 2>/dev/null); then
      echo "FATAL: Stable sealed-secrets private key not found in libsecret" >&2
      echo "Generate one first with: openssl genrsa 4096 | secret-tool store service sealed-secrets key private_key" >&2
      exit 1
    fi

    # Retrieve public key - MUST exist
    if ! cert=$(secret-tool lookup service sealed-secrets key public_key 2>/dev/null); then
      echo "FATAL: Stable sealed-secrets public key not found in libsecret" >&2
      echo "Generate one first - see bootstrap script error message for commands" >&2
      exit 1
    fi

    # Both exist - return them (NOT base64 encoded, they're stored as plain text)
    private_key_b64=$(echo "$private_key" | base64 -w0)
    cert_b64=$(echo "$cert" | base64 -w0)
    echo "{\"private_key\": \"$private_key_b64\", \"certificate\": \"$cert_b64\", \"exists\": \"true\"}"
EOF
  ]
}

# Generate Proxmox CSI storage secrets using stable sealed-secrets keypair
resource "null_resource" "proxmox_csi_sealed_secret" {
  # Re-run when PVE auth tokens change
  triggers = {
    csi_config_hash = sha256(jsonencode(data.external.pve_persistent_tokens["csi"].result.config_json))
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Create temporary secret file with CSI configuration
      csi_config='${data.external.pve_persistent_tokens["csi"].result.config_json}'

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

# Commit sealed secrets changes to git (only when they actually change)
resource "null_resource" "commit_sealed_secrets" {
  # Only run when sealed secret actually changes
  triggers = {
    sealed_secret_hash = filesha256("${path.root}/../../k8s/storage/proxmox-csi-sealed.yaml")
  }

  provisioner "local-exec" {
    command = <<-EOT
      cd ${path.root}/../..
      if ! git diff --quiet k8s/storage/proxmox-csi-sealed.yaml; then
        git add k8s/storage/proxmox-csi-sealed.yaml
        git commit -m "chore: update Proxmox CSI sealed secret

🔄 Generated with stable sealed-secrets keypair
🔒 Persistent auth token - survives VM lifecycle

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>"
        echo "✅ Committed updated Proxmox CSI sealed secret"
      else
        echo "ℹ️  Proxmox CSI sealed secret unchanged - no commit needed"
      fi
    EOT
  }

  depends_on = [null_resource.proxmox_csi_sealed_secret]
}

# NOTE: No cleanup provisioner here - persistent tokens only destroyed when this layer is explicitly destroyed