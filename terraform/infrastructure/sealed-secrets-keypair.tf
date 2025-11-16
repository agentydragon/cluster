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

# Import keypair from libsecret storage
locals {
  sealed_secrets_cert_pem = base64decode(data.external.sealed_secrets_keypair.result.certificate)
  sealed_secrets_key_pem  = base64decode(data.external.sealed_secrets_keypair.result.private_key)
}

# Apply our stable keypair to the cluster so sealed-secrets controller uses it
resource "kubernetes_secret" "sealed_secrets_key" {
  metadata {
    name      = "sealed-secrets-key"
    namespace = "kube-system"
    labels = {
      "sealedsecrets.bitnami.com/sealed-secrets-key" = "active"
    }
  }
  
  data = {
    "tls.crt" = local.sealed_secrets_cert_pem
    "tls.key" = local.sealed_secrets_key_pem  
  }
  
  type = "kubernetes.io/tls"
  
  depends_on = [helm_release.cilium_bootstrap]
}

# Random suffix to ensure unique key names (sealed-secrets keeps all keys)
resource "random_string" "key_suffix" {
  length  = 5
  special = false
  upper   = false
}

