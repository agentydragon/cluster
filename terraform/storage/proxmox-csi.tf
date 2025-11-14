# Proxmox CSI Sealed Secret Creation
# Run this after infrastructure terraform and GitOps sealed-secrets deployment

# Read outputs from pve-auth terraform
data "terraform_remote_state" "pve_auth" {
  backend = "local"
  config = {
    path = "${path.module}/../pve-auth/terraform.tfstate"
  }
}

locals {
  # Get complete CSI configuration from pve-auth module
  csi_cluster_config = data.terraform_remote_state.pve_auth.outputs.csi_config

  # Generate CSI config YAML with the complete cluster configuration
  csi_config = yamlencode({
    clusters = [local.csi_cluster_config]
  })
}

# Create sealed secret for Proxmox CSI credentials
resource "null_resource" "create_proxmox_csi_sealed_secret" {
  triggers = {
    config_content = local.csi_config
  }

  provisioner "local-exec" {
    command = <<-EOF
      kubectl create secret generic proxmox-csi-plugin \
        --namespace=csi-proxmox \
        --from-literal=config.yaml='${local.csi_config}' \
        --dry-run=client -o yaml | \
      kubeseal --format=yaml > ${path.module}/../../k8s/storage/proxmox-csi-sealed.yaml

      echo "Generated sealed secret at k8s/storage/proxmox-csi-sealed.yaml"
    EOF
  }
}