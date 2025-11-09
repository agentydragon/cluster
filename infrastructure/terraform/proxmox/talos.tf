locals {
  controller_nodes = [
    for i in range(var.controller_count) : {
      name    = "c${i}"
      address = cidrhost(var.cluster_node_network, var.cluster_node_network_first_controller_hostnum + i)
    }
  ]
  worker_nodes = [
    for i in range(var.worker_count) : {
      name    = "w${i}"
      address = cidrhost(var.cluster_node_network, var.cluster_node_network_first_worker_hostnum + i)
    }
  ]
  common_machine_config = {
    machine = {
      features = {
        # see https://www.talos.dev/v1.11/kubernetes-guides/configuration/kubeprism/
        kubePrism = {
          enabled = true
          port    = 7445
        }
        # see https://www.talos.dev/v1.11/talos-guides/network/host-dns/
        hostDNS = {
          enabled              = true
          forwardKubeDNSToHost = true
        }
      }
    }
    cluster = {
      # disable kubernetes discovery as its no longer compatible with k8s 1.32+.
      discovery = {
        enabled = false
        registries = {
          kubernetes = {
            disabled = true
          }
          service = {
            disabled = true
          }
        }
      }
      network = {
        cni = {
          name = "none"
        }
      }
      proxy = {
        disabled = true
      }
    }
  }
}

// see https://registry.terraform.io/providers/siderolabs/talos/0.9.0/docs/resources/machine_secrets
resource "talos_machine_secrets" "talos" {
  talos_version = "v${var.talos_version}"
}

// see https://registry.terraform.io/providers/siderolabs/talos/0.9.0/docs/data-sources/machine_configuration
data "talos_machine_configuration" "controller" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_secrets    = talos_machine_secrets.talos.machine_secrets
  machine_type       = "controlplane"
  talos_version      = "v${var.talos_version}"
  kubernetes_version = var.kubernetes_version
  examples           = false
  docs               = false
  config_patches = [
    yamlencode(local.common_machine_config),
    yamlencode({
      machine = {
        network = {
          interfaces = [
            # see https://www.talos.dev/v1.11/talos-guides/network/vip/
            {
              interface = "eth0"
              vip = {
                ip = var.cluster_vip
              }
            }
          ]
        }
        # Add Tailscale extension configuration
        install = {
          extensions = [
            {
              image = "ghcr.io/siderolabs/tailscale:latest"
            }
          ]
        }
      }
      cluster = {
        # Add Tailscale extension service config
        inlineManifests = [
          {
            name = "tailscale-extension"
            contents = yamlencode({
              apiVersion = "v1alpha1"
              kind       = "ExtensionServiceConfig"
              metadata = {
                name      = "tailscale"
                namespace = "kube-system"
              }
              spec = {
                services = [
                  {
                    name = "tailscale"
                    environment = [
                      {
                        name  = "TS_AUTHKEY"
                        value = var.headscale_auth_key
                      },
                      {
                        name  = "TS_EXTRA_ARGS"
                        value = "--login-server=${var.headscale_login_server} --accept-routes --advertise-routes=10.5.0.0/16"
                      }
                    ]
                  }
                ]
              }
            })
          }
        ]
      }
    }),
  ]
}

// see https://registry.terraform.io/providers/siderolabs/talos/0.9.0/docs/data-sources/machine_configuration
data "talos_machine_configuration" "worker" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_secrets    = talos_machine_secrets.talos.machine_secrets
  machine_type       = "worker"
  talos_version      = "v${var.talos_version}"
  kubernetes_version = var.kubernetes_version
  examples           = false
  docs               = false
  config_patches = [
    yamlencode(local.common_machine_config),
    yamlencode({
      machine = {
        # Add Tailscale extension configuration
        install = {
          extensions = [
            {
              image = "ghcr.io/siderolabs/tailscale:latest"
            }
          ]
        }
      }
      cluster = {
        # Add Tailscale extension service config
        inlineManifests = [
          {
            name = "tailscale-extension"
            contents = yamlencode({
              apiVersion = "v1alpha1"
              kind       = "ExtensionServiceConfig"
              metadata = {
                name      = "tailscale"
                namespace = "kube-system"
              }
              spec = {
                services = [
                  {
                    name = "tailscale"
                    environment = [
                      {
                        name  = "TS_AUTHKEY"
                        value = var.headscale_auth_key
                      },
                      {
                        name  = "TS_EXTRA_ARGS"
                        value = "--login-server=${var.headscale_login_server} --accept-routes"
                      }
                    ]
                  }
                ]
              }
            })
          }
        ]
      }
    }),
  ]
}

// see https://registry.terraform.io/providers/siderolabs/talos/0.9.0/docs/data-sources/client_configuration
data "talos_client_configuration" "talos" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.talos.client_configuration
  endpoints            = [for node in local.controller_nodes : node.address]
}

// see https://registry.terraform.io/providers/siderolabs/talos/0.9.0/docs/resources/cluster_kubeconfig
resource "talos_cluster_kubeconfig" "talos" {
  client_configuration = talos_machine_secrets.talos.client_configuration
  endpoint             = local.controller_nodes[0].address
  node                 = local.controller_nodes[0].address
  depends_on = [
    talos_machine_bootstrap.talos,
  ]
}

// see https://registry.terraform.io/providers/siderolabs/talos/0.9.0/docs/resources/machine_configuration_apply
resource "talos_machine_configuration_apply" "controller" {
  count                       = var.controller_count
  client_configuration        = talos_machine_secrets.talos.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controller.machine_configuration
  endpoint                    = local.controller_nodes[count.index].address
  node                        = local.controller_nodes[count.index].address
  config_patches = [
    yamlencode({
      machine = {
        network = {
          hostname = local.controller_nodes[count.index].name
        }
      }
    }),
  ]
  depends_on = [
    proxmox_virtual_environment_vm.controller,
  ]
}

// see https://registry.terraform.io/providers/siderolabs/talos/0.9.0/docs/resources/machine_configuration_apply
resource "talos_machine_configuration_apply" "worker" {
  count                       = var.worker_count
  client_configuration        = talos_machine_secrets.talos.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  endpoint                    = local.worker_nodes[count.index].address
  node                        = local.worker_nodes[count.index].address
  config_patches = [
    yamlencode({
      machine = {
        network = {
          hostname = local.worker_nodes[count.index].name
        }
      }
    }),
  ]
  depends_on = [
    proxmox_virtual_environment_vm.worker,
  ]
}

// see https://registry.terraform.io/providers/siderolabs/talos/0.9.0/docs/resources/machine_bootstrap
resource "talos_machine_bootstrap" "talos" {
  client_configuration = talos_machine_secrets.talos.client_configuration
  endpoint             = local.controller_nodes[0].address
  node                 = local.controller_nodes[0].address
  depends_on = [
    talos_machine_configuration_apply.controller,
  ]
}