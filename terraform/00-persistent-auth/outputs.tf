output "csi_config" {
  description = "Proxmox CSI configuration JSON for use by infrastructure layer"
  value       = jsondecode(data.external.pve_persistent_tokens["csi"].result.config_json)
  sensitive   = true
}

output "sealed_secrets_keypair" {
  description = "Sealed secrets keypair information"
  value = {
    exists      = data.external.sealed_secrets_keypair.result.exists
    private_key = data.external.sealed_secrets_keypair.result.private_key
    certificate = data.external.sealed_secrets_keypair.result.certificate
  }
  sensitive = true
}

output "persistent_auth_ready" {
  description = "Indicates that persistent auth layer is ready"
  value = {
    timestamp     = timestamp()
    csi_ready     = length(data.external.pve_persistent_tokens) > 0
    keypair_ready = data.external.sealed_secrets_keypair.result.exists == "true"
  }
}