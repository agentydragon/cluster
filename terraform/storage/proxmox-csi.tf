# Proxmox CSI Sealed Secret Creation
# Run this after infrastructure terraform and GitOps sealed-secrets deployment

# Read outputs from infrastructure terraform
data "terraform_remote_state" "infrastructure" {
  backend = "local"
  config = {
    path = "${path.module}/../infrastructure/terraform.tfstate"
  }
}

locals {
  # Get complete CSI configuration from infrastructure terraform
  csi_cluster_config = data.terraform_remote_state.infrastructure.outputs.proxmox_csi_config

  # Generate CSI config YAML with the complete cluster configuration
  # Use JSON encoding to preserve boolean types, then wrap in YAML clusters array
  csi_config = "clusters:\n- ${jsonencode(local.csi_cluster_config)}"
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