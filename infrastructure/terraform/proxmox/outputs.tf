output "controllers" {
  description = "Controller node IP addresses"
  value       = join(",", [for node in local.controller_nodes : node.address])
}

output "workers" {
  description = "Worker node IP addresses"
  value       = join(",", [for node in local.worker_nodes : node.address])
}

output "talosconfig" {
  description = "Talos client configuration"
  value       = data.talos_client_configuration.talos.talos_config
  sensitive   = true
}

output "kubeconfig" {
  description = "Kubernetes client configuration"
  value       = talos_cluster_kubeconfig.talos.kubeconfig_raw
  sensitive   = true
}
