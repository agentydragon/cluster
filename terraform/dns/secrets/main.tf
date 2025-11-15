terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.33.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.5.0"
    }
  }
}

# Generate secure PowerDNS API key
resource "random_password" "powerdns_api_key" {
  length  = 32
  special = false

  lifecycle {
    ignore_changes = [length, special]
  }
}

# Store API key in Vault
resource "vault_generic_secret" "powerdns_api_key" {
  path = "kv/powerdns/api"

  data_json = jsonencode({
    api_key = random_password.powerdns_api_key.result
  })

  lifecycle {
    ignore_changes = [data_json]
  }
}

# Update PowerDNS deployment to use production secret (replacing bootstrap)
resource "kubernetes_deployment" "powerdns_update" {
  metadata {
    name      = "powerdns"
    namespace = "dns-system"

    annotations = {
      "deployment.kubernetes.io/revision" = "2" # Force update
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "powerdns"
      }
    }

    template {
      metadata {
        labels = {
          app = "powerdns"
        }
        annotations = {
          "cluster.bootstrap/secret-source" = "vault"
        }
      }

      spec {
        container {
          name  = "powerdns"
          image = "powerdns/pdns-auth-master:latest"

          env {
            name = "PDNS_API_KEY"
            value_from {
              secret_key_ref {
                name = "powerdns-api-key-production" # Use Vault-backed secret
                key  = "powerdns_api_key"
              }
            }
          }

          port {
            container_port = 53
            name           = "dns-udp"
            protocol       = "UDP"
          }
          port {
            container_port = 53
            name           = "dns-tcp"
            protocol       = "TCP"
          }
          port {
            container_port = 8081
            name           = "api"
            protocol       = "TCP"
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/powerdns"
          }
          volume_mount {
            name       = "data"
            mount_path = "/var/lib/powerdns"
          }

          liveness_probe {
            tcp_socket {
              port = 53
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path   = "/api/v1/servers/localhost"
              port   = 8081
              scheme = "HTTP"
            }
            initial_delay_seconds = 10
            period_seconds        = 5
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }
        }

        volume {
          name = "config"
          config_map {
            name = "powerdns-config"
          }
        }
        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = "powerdns-data"
          }
        }
      }
    }
  }

  # Wait for Vault-backed secret to be ready
  depends_on = [vault_generic_secret.powerdns_api_key]
}

# Remove bootstrap ExternalSecret (terraform will delete it)
resource "kubernetes_manifest" "remove_bootstrap_external_secret" {
  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "powerdns-api-key-bootstrap"
      namespace = "dns-system"
    }
  }

  # This resource exists only to be deleted by terraform
  lifecycle {
    ignore_changes = all
  }
}

# Remove bootstrap Password generator
resource "kubernetes_manifest" "remove_bootstrap_password" {
  manifest = {
    apiVersion = "generators.external-secrets.io/v1alpha1"
    kind       = "Password"
    metadata = {
      name      = "powerdns-api-key-generator"
      namespace = "dns-system"
    }
  }

  lifecycle {
    ignore_changes = all
  }
}

# Output for reference
output "powerdns_api_key" {
  value     = random_password.powerdns_api_key.result
  sensitive = true
}