# Attic JWT Token Generation with LibSecret Storage
# JWT token for Attic HTTP API authentication
# Stored in system keyring for persistence across destroy/apply cycles

# Generate Attic JWT token if not exists in libsecret
resource "null_resource" "attic_jwt_token_generate" {
  provisioner "local-exec" {
    command = <<-EOT
      set -e

      # Check if JWT token already exists
      if ! secret-tool lookup service attic key jwt_token 2>/dev/null; then
        echo "🔑 Generating new Attic JWT token..."

        # Generate 64 random bytes, base64 encode
        jwt_token=$(openssl rand 64 | base64 -w0)

        # Store in libsecret
        echo "$jwt_token" | secret-tool store --label='Attic JWT token' service attic key jwt_token

        echo "✅ Attic JWT token generated and stored in libsecret"
      else
        echo "ℹ️  Attic JWT token already exists in libsecret"
      fi
    EOT
  }
}

# Retrieve stable JWT token from libsecret
data "external" "attic_jwt_token" {
  depends_on = [null_resource.attic_jwt_token_generate]

  program = ["bash", "-c", <<-EOF
    set -e

    # Retrieve token - MUST exist
    if ! jwt_token=$(secret-tool lookup service attic key jwt_token 2>/dev/null); then
      echo "FATAL: Attic JWT token not found in libsecret" >&2
      exit 1
    fi

    # Return token
    echo "{\"jwt_token\": \"$jwt_token\"}"
  EOF
  ]
}

# Generate SealedSecret for Attic JWT token
resource "null_resource" "attic_jwt_token_sealed_secret" {
  triggers = {
    # Re-run when token changes (unlikely but possible)
    token_hash = sha256(data.external.attic_jwt_token.result.jwt_token)
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Retrieve token from libsecret
      jwt_token=$(secret-tool lookup service attic key jwt_token)

      # Create kubernetes secret YAML
      cat > /tmp/attic-jwt-token.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: attic-jwt-token
  namespace: nix-cache
type: Opaque
stringData:
  jwt-token: "$jwt_token"
EOF

      # Seal the secret using stable keypair from libsecret
      secret-tool lookup service sealed-secrets key public_key > /tmp/sealed-secrets-cert.pem
      kubeseal --cert /tmp/sealed-secrets-cert.pem \
        --format=yaml < /tmp/attic-jwt-token.yaml > ${path.root}/../../k8s/applications/nix-cache/jwt-token-sealed.yaml
      rm /tmp/sealed-secrets-cert.pem

      # Clean up temporary file
      rm /tmp/attic-jwt-token.yaml

      echo "✅ Generated sealed secret for Attic JWT token"
    EOT
  }

  depends_on = [data.external.attic_jwt_token]
}

# Commit sealed secrets changes to git
resource "null_resource" "commit_attic_jwt_sealed_secret" {
  triggers = {
    # Depend on the sealed secret generation
    sealed_secret_id = null_resource.attic_jwt_token_sealed_secret.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      cd ${path.root}/../..
      if [ -f k8s/applications/nix-cache/jwt-token-sealed.yaml ]; then
        if ! git diff --quiet k8s/applications/nix-cache/jwt-token-sealed.yaml 2>/dev/null; then
          git add k8s/applications/nix-cache/jwt-token-sealed.yaml
          git commit -m "chore: update Attic JWT token sealed secret

🔄 Generated with stable sealed-secrets keypair
🔒 Persistent JWT token - survives cluster lifecycle

🤖 Generated with Claude Code

Co-Authored-By: Claude <noreply@anthropic.com>"
          echo "✅ Committed updated Attic JWT token sealed secret"
        else
          echo "ℹ️  Attic JWT token sealed secret unchanged - no commit needed"
        fi
      else
        echo "⚠️  Attic JWT token sealed secret file not found - skipping commit"
      fi
    EOT
  }

  depends_on = [null_resource.attic_jwt_token_sealed_secret]
}

# Output for verification
output "attic_jwt_token_configured" {
  value       = true
  description = "Attic JWT token configured in libsecret"
}
