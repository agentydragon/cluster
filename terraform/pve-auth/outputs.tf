# Output Proxmox credentials for consumption by other terraform modules

output "terraform_token" {
  description = "Proxmox terraform API token (id=secret format)"
  value       = local.credentials["proxmox-terraform-token"]
  sensitive   = true
}

output "csi_token" {
  description = "Proxmox CSI API token (id=secret format)"
  value       = local.credentials["proxmox-csi-token"]
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