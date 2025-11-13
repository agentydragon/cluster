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

# Output first controller kubeconfig (reliable, for bootstrap and debugging)
output "kubeconfig_first_controller" {
  description = "Kubernetes client configuration for first controller (reliable)"
  value       = talos_cluster_kubeconfig.talos.kubeconfig_raw
  sensitive   = true
}

# Health check: verify VIP is reachable before generating VIP kubeconfig
resource "terraform_data" "vip_health_check" {
  provisioner "local-exec" {
    command = "ping -c 3 ${var.cluster_vip} && curl -k --connect-timeout 5 https://${var.cluster_vip}:6443/version"
  }
  depends_on = [talos_cluster_kubeconfig.talos]
}

# Generate VIP kubeconfig by modifying YAML structure
locals {
  kubeconfig_parsed = yamldecode(talos_cluster_kubeconfig.talos.kubeconfig_raw)
  kubeconfig_vip = yamlencode(merge(local.kubeconfig_parsed, {
    clusters = [
      merge(local.kubeconfig_parsed.clusters[0], {
        cluster = merge(local.kubeconfig_parsed.clusters[0].cluster, {
          server = "https://${var.cluster_vip}:6443"
        })
      })
    ]
  }))
}

# Output VIP kubeconfig (high availability, for daily use)
output "kubeconfig_vip" {
  description = "Kubernetes client configuration using VIP (high availability)"
  value       = local.kubeconfig_vip
  sensitive   = true
  depends_on  = [terraform_data.vip_health_check]
}

# Default kubeconfig (backwards compatibility - points to VIP)
output "kubeconfig" {
  description = "Default Kubernetes client configuration (VIP for HA)"
  value       = local.kubeconfig_vip
  sensitive   = true
  depends_on  = [terraform_data.vip_health_check]
}
