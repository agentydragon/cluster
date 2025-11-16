# INFRASTRUCTURE MODULE OUTPUTS

output "kubeconfig" {
  description = "Generated kubeconfig for cluster access"
  value       = talos_cluster_kubeconfig.talos.kubeconfig_raw
  sensitive   = true
}

output "talos_config" {
  description = "Talos client configuration"
  value       = data.talos_client_configuration.talos.talos_config
  sensitive   = true
}

output "cluster_endpoint" {
  description = "Kubernetes API cluster endpoint"
  value       = local.cluster_vip_endpoint
}

output "controlplane_ips" {
  description = "Control plane node IP addresses"
  value       = [for node in local.nodes_by_type.controlplane : node.ip_address]
}

output "worker_ips" {
  description = "Worker node IP addresses"
  value       = [for node in local.nodes_by_type.worker : node.ip_address]
}