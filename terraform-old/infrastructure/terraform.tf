# TERRAFORM CONFIGURATION - inherits providers from /terraform.tf
# Custom backend configuration for infrastructure

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.86.0"  # From centralized terraform.tf
    }
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.9.0"   # From centralized terraform.tf
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3.0"   # From centralized terraform.tf
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5.0"   # From centralized terraform.tf
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1.0"   # From centralized terraform.tf
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2.0"   # From centralized terraform.tf
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38.0"  # From centralized terraform.tf
    }
    flux = {
      source  = "fluxcd/flux"
      version = "~> 1.7.0"   # From centralized terraform.tf
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7.0"   # From centralized terraform.tf
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}