# Define all nodes in a single place
locals {
  # Global configuration shared by all nodes
  global_config = {
    headscale_api_key      = var.headscale_api_key
    headscale_login_server = var.headscale_login_server
  }

  # Define all cluster nodes - 3 controllers + 2 workers
  nodes = {
    # Controller nodes
    c0 = {
      type       = "controller"
      vm_id      = 105
      ip_address = cidrhost(var.cluster_node_network, var.cluster_node_network_first_controller_hostnum) # Should be 10.0.0.11
    }
    c1 = {
      type       = "controller"
      vm_id      = 106
      ip_address = cidrhost(var.cluster_node_network, var.cluster_node_network_first_controller_hostnum + 1) # Should be 10.0.0.12
    }
    c2 = {
      type       = "controller"
      vm_id      = 107
      ip_address = cidrhost(var.cluster_node_network, var.cluster_node_network_first_controller_hostnum + 2) # Should be 10.0.0.13
    }

    # Worker nodes
    w0 = {
      type       = "worker"
      vm_id      = 108
      ip_address = cidrhost(var.cluster_node_network, var.cluster_node_network_first_worker_hostnum) # Should be 10.0.0.21
    }
    w1 = {
      type       = "worker"
      vm_id      = 109
      ip_address = cidrhost(var.cluster_node_network, var.cluster_node_network_first_worker_hostnum + 1) # Should be 10.0.0.22
    }
  }

  # Split nodes by type for outputs and bootstrap
  controller_nodes = { for k, v in local.nodes : k => v if v.type == "controller" }
  worker_nodes     = { for k, v in local.nodes : k => v if v.type == "worker" }
}

# Generate machine secrets once for the entire cluster
resource "talos_machine_secrets" "talos" {
  talos_version = "v${var.talos_version}"
}

# Create each node using the module
module "nodes" {
  for_each = local.nodes
  source   = "./modules/talos-node"

  # Node-specific configuration
  node_name  = each.key
  node_type  = each.value.type
  vm_id      = each.value.vm_id
  ip_address = each.value.ip_address

  # Shared configuration
  gateway            = var.cluster_node_network_gateway
  proxmox_node_name  = var.proxmox_pve_node_name
  prefix             = var.prefix
  talos_version      = var.talos_version
  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  cluster_vip        = var.cluster_vip
  kubernetes_version = var.kubernetes_version
  machine_secrets    = talos_machine_secrets.talos
  global_config      = local.global_config
}

# Bootstrap the cluster (using first controller)
resource "talos_machine_bootstrap" "talos" {
  client_configuration = talos_machine_secrets.talos.client_configuration
  endpoint             = local.controller_nodes.c0.ip_address
  node                 = local.controller_nodes.c0.ip_address
  depends_on           = [module.nodes]
}

# Generate kubeconfig (uses VIP for HA after bootstrap completes)
# Note: Bootstrap still uses first controller IP, but final kubeconfig uses VIP
resource "talos_cluster_kubeconfig" "talos" {
  client_configuration = talos_machine_secrets.talos.client_configuration
  endpoint             = var.cluster_vip                 # Use VIP for HA kubectl access
  node                 = var.cluster_vip                 # Also use VIP for kubeconfig server field
  depends_on           = [talos_machine_bootstrap.talos] # Wait for bootstrap AND VIP to be established
}

# Generate talos client config
data "talos_client_configuration" "talos" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.talos.client_configuration
  endpoints            = [for node in local.controller_nodes : node.ip_address]
}
