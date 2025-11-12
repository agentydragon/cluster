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

# Health check: verify VIP is reachable before generating VIP kubeconfig
resource "terraform_data" "vip_health_check" {
  provisioner "local-exec" {
    command = "ping -c 3 ${var.cluster_vip} && curl -k --connect-timeout 5 https://${var.cluster_vip}:6443/version"
  }
  depends_on = [talos_cluster_kubeconfig.talos]
}

output "kubeconfig" {
  description = "Kubernetes client configuration (corrected to use VIP after health check)"
  value       = replace(talos_cluster_kubeconfig.talos.kubeconfig_raw, var.cluster_endpoint, "https://${var.cluster_vip}:6443")
  sensitive   = true
  depends_on  = [terraform_data.vip_health_check]
}

