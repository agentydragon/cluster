terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.36"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.5"
    }
  }
}