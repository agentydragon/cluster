# Core Proxmox connection variables
# proxmox_api_url is auto-computed from proxmox_node_name

variable "proxmox_tls_insecure" {
  description = "Allow self-signed certificates when talking to Proxmox."
  type        = bool
  default     = true # Sensible default for most setups
}


# SSH no longer needed with content_type="import" and Proxmox VE 8.4+

variable "proxmox_node_name" {
  description = "Name of the Proxmox node where VMs will be created"
  type        = string
  default     = "atlas"
}

# Talos cluster configuration
variable "cluster_name" {
  description = "Name of the Talos cluster"
  type        = string
  default     = "talos-cluster"
}


variable "cluster_vip" {
  description = "Virtual IP for HA cluster access (different from bootstrap endpoint)"
  type        = string
  default     = "10.0.3.1" # Cluster API VIP in dedicated VIP subnet
}

# Network configuration - simple and explicit
variable "cluster_networks" {
  description = "Network configuration for cluster nodes"
  type = object({
    gateway         = string
    controller_cidr = string # Controllers subnet CIDR
    worker_cidr     = string # Workers subnet CIDR
  })
  default = {
    gateway         = "10.0.0.1"
    controller_cidr = "10.0.1.0/24"
    worker_cidr     = "10.0.2.0/24"
  }
}

variable "controller_count" {
  description = "Number of controller nodes (production: 3 for HA)"
  type        = number
  default     = 3
  validation {
    condition     = var.controller_count >= 1 && var.controller_count <= 10
    error_message = "Controller count must be between 1 and 10."
  }
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2
  validation {
    condition     = var.worker_count >= 0 && var.worker_count <= 20
    error_message = "Worker count must be between 0 and 20."
  }
}

variable "prefix" {
  description = "Prefix for VM names"
  type        = string
  default     = "talos"
}

variable "talos_version" {
  description = "Talos version for the cluster (with v prefix)"
  type        = string
  default     = "v1.11.2"
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.32.1"
}

variable "vm_id_ranges" {
  description = "VM ID ranges for different node types"
  type = object({
    controller_start = number
    worker_start     = number
  })
  default = {
    controller_start = 1500
    worker_start     = 2000
  }
}

# Tailscale integration

variable "headscale_user" {
  description = "Headscale user for pre-auth key generation."
  type        = string
  # No default - must be specified in terraform.tfvars
}

variable "headscale_login_server" {
  description = "Headscale login server URL."
  type        = string
  default     = "https://agentydragon.com:8080"
}

# GitHub configuration for Flux GitOps
variable "github_owner" {
  description = "GitHub owner/organization for Flux GitOps"
  type        = string
  default     = "agentydragon"
}

variable "github_repository" {
  description = "GitHub repository name for Flux GitOps"
  type        = string
  default     = "cluster"
}
