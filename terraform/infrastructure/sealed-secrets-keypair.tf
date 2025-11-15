# Sealed Secrets Keypair Generation
# For test clusters: Generate stable keypair in Terraform
# For production: Use external key management or separate control plane

# Generate deterministic keypair that survives destroy/apply cycles
resource "tls_private_key" "sealed_secrets" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "sealed_secrets" {
  private_key_pem = tls_private_key.sealed_secrets.private_key_pem

  subject {
    common_name = "sealed-secrets"
  }

  validity_period_hours = 87600 # 10 years

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
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
    "tls.crt" = tls_self_signed_cert.sealed_secrets.cert_pem
    "tls.key" = tls_private_key.sealed_secrets.private_key_pem
  }

  depends_on = [
    helm_release.cilium_bootstrap # Native Helm wait ensures healthy CNI
  ]
}

# Random suffix to ensure unique key names (sealed-secrets keeps all keys)
resource "random_string" "key_suffix" {
  length  = 5
  lower   = true
  upper   = false
  numeric = true
  special = false
}

# Output the public key for sealing secrets outside terraform
output "sealed_secrets_cert" {
  value       = tls_self_signed_cert.sealed_secrets.cert_pem
  description = "Public certificate for sealing secrets"
  sensitive   = false
}