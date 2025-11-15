# Sealed Secrets Keypair Generation with LibSecret Storage
# Stores keypair in system keyring for true persistence across destroy/apply cycles

# Try to retrieve existing keypair from libsecret keyring
data "external" "sealed_secrets_keypair" {
  program = ["bash", "-c", <<-EOF
    set -e

    # Try to retrieve existing private key
    if private_key=$(secret-tool lookup service sealed-secrets key private_key 2>/dev/null); then
      # Try to retrieve existing certificate
      if cert=$(secret-tool lookup service sealed-secrets key certificate 2>/dev/null); then
        # Both exist - return them (already base64 encoded in keyring)
        echo "{\"private_key\": \"$private_key\", \"certificate\": \"$cert\", \"exists\": \"true\"}"
        exit 0
      fi
    fi

    # Generate new keypair if not found
    temp_key=$(mktemp)
    temp_cert=$(mktemp)

    # Generate new RSA private key
    openssl genrsa -out "$temp_key" 4096

    # Generate self-signed certificate
    openssl req -new -x509 -key "$temp_key" -out "$temp_cert" -days 3650 \
      -subj "/CN=sealed-secrets" \
      -addext "keyUsage=keyEncipherment,digitalSignature" \
      -addext "extendedKeyUsage=serverAuth"

    # Base64 encode for storage
    private_key=$(cat "$temp_key" | base64 -w0)
    cert=$(cat "$temp_cert" | base64 -w0)

    # Store in keyring (base64 encoded)
    echo "$private_key" | secret-tool store --label="Sealed Secrets Private Key" service sealed-secrets key private_key
    echo "$cert" | secret-tool store --label="Sealed Secrets Certificate" service sealed-secrets key certificate

    # Cleanup temp files
    rm -f "$temp_key" "$temp_cert"

    echo "{\"private_key\": \"$private_key\", \"certificate\": \"$cert\", \"exists\": \"false\"}"
EOF
  ]
}

# Import keypair from libsecret storage
locals {
  sealed_secrets_private_key_pem = base64decode(data.external.sealed_secrets_keypair.result.private_key)
  sealed_secrets_cert_pem        = base64decode(data.external.sealed_secrets_keypair.result.certificate)
}

# Deploy keypair as Kubernetes secret before sealed-secrets controller starts
resource "kubernetes_secret" "sealed_secrets_key" {
  metadata {
    name      = "sealed-secrets-key${random_string.key_suffix.result}"
    namespace = "kube-system"
    labels = {
      "sealedsecrets.bitnami.com/sealed-secrets-key" = "active"
    }
  }

  type = "kubernetes.io/tls"
  data = {
    "tls.crt" = base64encode(local.sealed_secrets_cert_pem)
    "tls.key" = base64encode(local.sealed_secrets_private_key_pem)
  }

  depends_on = [
    helm_release.cilium_bootstrap # Native Helm wait ensures healthy CNI
  ]
}

# Random suffix to ensure unique key names (sealed-secrets keeps all keys)
resource "random_string" "key_suffix" {
  length  = 5
  special = false
  upper   = false
}

