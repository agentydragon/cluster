# Proxmox Volume Cleanup for Retain Policy
# Cleans up Proxmox storage volumes during terraform destroy while maintaining
# Retain policy for safety (accidental PVC deletion doesn't lose data)

resource "null_resource" "cleanup_proxmox_volumes" {
  # This resource depends on Cilium to ensure it runs after PVCs are cleaned up
  # but before the cluster is fully destroyed
  depends_on = [helm_release.cilium_bootstrap]

  triggers = {
    # Track cluster instance to ensure cleanup runs on each destroy
    cluster_endpoint = var.cluster_endpoint
    proxmox_host     = "root@atlas"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "${path.module}/scripts/cleanup-proxmox-volumes.py ${path.module}/kubeconfig ${self.triggers.proxmox_host}"
  }
}
