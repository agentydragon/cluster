# CONSOLIDATED CLUSTER TERRAFORM CONFIGURATION
# Single terraform managing all cluster layers with proper dependencies

# Layer control variable
variable "deploy_layer" {
  description = "Which layer to deploy: pve-auth, infrastructure, gitops, dns, or all"
  type        = string
  default     = "all"
  
  validation {
    condition     = contains(["pve-auth", "infrastructure", "gitops", "dns", "storage", "all"], var.deploy_layer)
    error_message = "deploy_layer must be one of: pve-auth, infrastructure, gitops, dns, storage, all"
  }
}

# Common variables
variable "proxmox_host" {
  description = "Proxmox host for SSH access"
  type        = string
  default     = "atlas"
}

variable "talos_version" {
  description = "Talos Linux version"
  type        = string
  default     = "v1.9.1"
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.32.1"
}

variable "cluster_domain" {
  description = "Cluster domain name"
  type        = string
  default     = "test-cluster.agentydragon.com"
}

variable "github_owner" {
  description = "GitHub repository owner"
  type        = string
  default     = "agentydragon"
}

variable "github_repository" {
  description = "GitHub repository name"
  type        = string
  default     = "cluster"
}

# Local values
locals {
  deploy_pve_auth     = contains(["all", "pve-auth"], var.deploy_layer)
  deploy_infrastructure = contains(["all", "infrastructure"], var.deploy_layer)
  deploy_gitops       = contains(["all", "gitops"], var.deploy_layer)
  deploy_dns          = contains(["all", "dns"], var.deploy_layer)
  deploy_storage      = contains(["all", "storage"], var.deploy_layer)
}