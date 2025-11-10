output "controllers" {
  description = "Controller node IP addresses"
  value       = join(",", [for node in local.controller_nodes : node.ip_address])
}

output "workers" {
  description = "Worker node IP addresses"
  value       = join(",", [for node in local.worker_nodes : node.ip_address])
}

output "all_nodes" {
  description = "All node details"
  value = {
    for name, node in module.nodes : name => {
      ip_address = node.ip_address
      vm_id      = node.vm_id
      node_name  = node.node_name
    }
  }
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
