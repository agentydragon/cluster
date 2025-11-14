# Output Proxmox credentials for consumption by other terraform modules

output "terraform_token" {
  description = "Proxmox terraform API token (id=secret format)"
  value       = data.keyring_secret.terraform_token.secret
  sensitive   = true
}

output "csi_token" {
  description = "Proxmox CSI API token (id=secret format)"
  value       = data.keyring_secret.csi_token.secret
  sensitive   = true
}

output "api_url" {
  description = "Proxmox API URL"
  value       = "https://atlas:8006/api2/json"
  sensitive   = false
}

output "tls_insecure" {
  description = "Proxmox TLS insecure setting"
  value       = true
  sensitive   = false
}