terraform {
  required_version = "~> 1.6"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.86.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.9.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4.0"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
    flux = {
      source  = "fluxcd/flux"
      version = "~> 1.7"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

# Read Proxmox credentials from pve-auth module
data "terraform_remote_state" "pve_auth" {
  backend = "local"
  config = {
    path = "../pve-auth/terraform.tfstate"
  }
}

# See: https://registry.terraform.io/providers/bpg/proxmox/latest/docs#argument-reference
# See environment variables at: https://github.com/bpg/terraform-provider-proxmox/blob/v0.84.1/proxmoxtf/provider/provider.go#L52-L61
provider "proxmox" {
  endpoint  = data.terraform_remote_state.pve_auth.outputs.csi_config.url
  insecure  = tobool(data.terraform_remote_state.pve_auth.outputs.csi_config.insecure)
  api_token = data.terraform_remote_state.pve_auth.outputs.terraform_token
}

provider "helm" {
  kubernetes {
    config_path = local_file.kubeconfig.filename
  }
}

provider "kubernetes" {
  config_path = local_file.kubeconfig.filename
}

provider "flux" {
  kubernetes = {
    config_path = local_file.kubeconfig.filename
  }
  git = {
    url = "https://github.com/${var.github_owner}/${var.github_repository}.git"
    http = {
      username = "git"
      password = data.external.github_token.result.token
    }
  }
}
