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
  # Extract CSI credentials from infrastructure state
  csi_token_id         = data.terraform_remote_state.infrastructure.outputs.proxmox_csi_token_id
  csi_token_secret     = data.terraform_remote_state.infrastructure.outputs.proxmox_csi_token_secret
  csi_api_url          = data.terraform_remote_state.infrastructure.outputs.proxmox_csi_api_url
  proxmox_tls_insecure = data.terraform_remote_state.infrastructure.outputs.proxmox_tls_insecure
}

# Generate CSI config content
locals {
  csi_config = yamlencode({
    clusters = [{
      url          = local.csi_api_url
      insecure     = local.proxmox_tls_insecure
      token_id     = local.csi_token_id
      token_secret = local.csi_token_secret
      region       = "cluster"
    }]
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