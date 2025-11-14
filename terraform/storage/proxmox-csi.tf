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
  csi_token            = data.terraform_remote_state.infrastructure.outputs.proxmox_csi_token
  csi_api_url          = data.terraform_remote_state.infrastructure.outputs.proxmox_csi_api_url
  proxmox_tls_insecure = data.terraform_remote_state.infrastructure.outputs.proxmox_tls_insecure

  # Split the token into ID and secret parts for Proxmox CSI plugin
  token_parts  = split("=", local.csi_token)
  token_id     = local.token_parts[0]
  token_secret = local.token_parts[1]

  # Generate CSI config content using separate token_id and token_secret
  csi_config = yamlencode({
    clusters = [{
      url          = local.csi_api_url
      insecure     = local.proxmox_tls_insecure
      token_id     = local.token_id
      token_secret = local.token_secret
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