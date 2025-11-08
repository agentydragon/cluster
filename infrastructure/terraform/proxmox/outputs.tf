output "talos_nodes" {
  description = "Provisioned Talos VMs and their primary attributes."
  value = {
    for name, node in proxmox_virtual_environment_vm.talos_nodes : name => {
      id        = node.id
      vm_id     = node.vm_id
      node_name = node.node_name
      tags      = node.tags
    }
  }
}
