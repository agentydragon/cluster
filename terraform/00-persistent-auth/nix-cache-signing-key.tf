# Nix Cache Signing Key Generation with LibSecret Storage
# Stores signing keypair in system keyring for persistence across destroy/apply cycles

# Generate Nix signing key if not exists in libsecret
resource "null_resource" "nix_cache_signing_key_generate" {
  provisioner "local-exec" {
    command = <<-EOT
      set -e

      # Check if signing key already exists
      if ! secret-tool lookup service nix-cache key signing_private 2>/dev/null; then
        echo "🔑 Generating new Nix cache signing key..."

        # Generate keypair using nix-store
        nix-store --generate-binary-cache-key cache.test-cluster.agentydragon.com-1 \
          /tmp/nix-cache-private.key \
          /tmp/nix-cache-public.key

        # Store in libsecret
        secret-tool store --label='Nix cache signing private key' service nix-cache key signing_private < /tmp/nix-cache-private.key
        secret-tool store --label='Nix cache signing public key' service nix-cache key signing_public < /tmp/nix-cache-public.key

        # Clean up temporary files
        rm /tmp/nix-cache-private.key /tmp/nix-cache-public.key

        echo "✅ Nix cache signing key generated and stored in libsecret"
      else
        echo "ℹ️  Nix cache signing key already exists in libsecret"
      fi
    EOT
  }
}

# Retrieve stable signing key from libsecret
data "external" "nix_cache_signing_key" {
  depends_on = [null_resource.nix_cache_signing_key_generate]

  program = ["bash", "-c", <<-EOF
    set -e

    # Retrieve keys - MUST exist
    if ! private_key=$(secret-tool lookup service nix-cache key signing_private 2>/dev/null); then
      echo "FATAL: Nix cache signing private key not found in libsecret" >&2
      exit 1
    fi

    if ! public_key=$(secret-tool lookup service nix-cache key signing_public 2>/dev/null); then
      echo "FATAL: Nix cache signing public key not found in libsecret" >&2
      exit 1
    fi

    # Return base64-encoded keys
    private_key_b64=$(echo "$private_key" | base64 -w0)
    public_key_b64=$(echo "$public_key" | base64 -w0)

    echo "{\"private_key\": \"$private_key_b64\", \"public_key\": \"$public_key_b64\"}"
  EOF
  ]
}

# Generate SealedSecret for Nix cache signing key
resource "null_resource" "nix_cache_signing_key_sealed_secret" {
  triggers = {
    # Re-run when keys change (unlikely but possible)
    keys_hash = sha256("${data.external.nix_cache_signing_key.result.private_key}:${data.external.nix_cache_signing_key.result.public_key}")
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Retrieve keys from libsecret
      private_key=$(secret-tool lookup service nix-cache key signing_private)
      public_key=$(secret-tool lookup service nix-cache key signing_public)

      # Create kubernetes secret YAML
      cat > /tmp/nix-cache-signing-key.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: nix-cache-signing-key
  namespace: nix-cache
type: Opaque
stringData:
  signing-key.sec: |
$(echo "$private_key" | sed 's/^/    /')
  signing-key.pub: |
$(echo "$public_key" | sed 's/^/    /')
EOF

      # Seal the secret using stable keypair from libsecret
      secret-tool lookup service sealed-secrets key public_key > /tmp/sealed-secrets-cert.pem
      kubeseal --cert /tmp/sealed-secrets-cert.pem \
        --format=yaml < /tmp/nix-cache-signing-key.yaml > ${path.root}/../../k8s/applications/nix-cache/signing-key-sealed.yaml
      rm /tmp/sealed-secrets-cert.pem

      # Clean up temporary file
      rm /tmp/nix-cache-signing-key.yaml

      echo "✅ Generated sealed secret for Nix cache signing key"
    EOT
  }

  depends_on = [data.external.nix_cache_signing_key]
}

# Commit sealed secrets changes to git
resource "null_resource" "commit_nix_cache_sealed_secret" {
  triggers = {
    # Depend on the sealed secret generation
    sealed_secret_id = null_resource.nix_cache_signing_key_sealed_secret.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      cd ${path.root}/../..
      if [ -f k8s/applications/nix-cache/signing-key-sealed.yaml ]; then
        if ! git diff --quiet k8s/applications/nix-cache/signing-key-sealed.yaml 2>/dev/null; then
          git add k8s/applications/nix-cache/signing-key-sealed.yaml
          git commit -m "chore: update Nix cache signing key sealed secret

🔄 Generated with stable sealed-secrets keypair
🔒 Persistent signing key - survives cluster lifecycle

🤖 Generated with Claude Code

Co-Authored-By: Claude <noreply@anthropic.com>"
          echo "✅ Committed updated Nix cache sealed secret"
        else
          echo "ℹ️  Nix cache sealed secret unchanged - no commit needed"
        fi
      else
        echo "⚠️  Nix cache sealed secret file not found - skipping commit"
      fi
    EOT
  }

  depends_on = [null_resource.nix_cache_signing_key_sealed_secret]
}

# Output public key for NixOS host configuration
output "nix_cache_public_key" {
  value       = data.external.nix_cache_signing_key.result.public_key
  description = "Nix cache signing public key (base64-encoded) for nix.conf trusted-public-keys"
  sensitive   = false
}
