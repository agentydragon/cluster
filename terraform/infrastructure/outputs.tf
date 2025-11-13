output "controllers" {
  description = "Controller node IP addresses"
  value       = [for node in local.nodes_by_type.controlplane : node.ip_address]
}

output "workers" {
  description = "Worker node IP addresses"
  value       = [for node in local.nodes_by_type.worker : node.ip_address]
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

# Bootstrap kubeconfig (first controller, for debugging)
output "kubeconfig_bootstrap" {
  description = "Kubernetes client configuration for first controller (debugging only)"
  value       = talos_cluster_kubeconfig.talos.kubeconfig_raw
  sensitive   = true
}

# Cluster configuration for health check script (DRY principle)
output "cluster_config" {
  description = "Complete cluster configuration for external tooling"
  value = {
    vip      = var.cluster_vip
    api_port = 6443
  }
}

# Write kubeconfig for direnv integration (already points to VIP)
resource "local_file" "kubeconfig" {
  content    = talos_cluster_kubeconfig.talos.kubeconfig_raw
  filename   = "${path.module}/kubeconfig"
  depends_on = [talos_cluster_kubeconfig.talos]
}

# Write talosconfig for health check script
resource "local_file" "talosconfig" {
  content    = data.talos_client_configuration.talos.talos_config
  filename   = "${path.module}/talosconfig.yml"
  depends_on = [data.talos_client_configuration.talos]
}




