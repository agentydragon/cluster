# Core Proxmox connection variables
variable "pm_api_url" {
  description = "Base URL for the Proxmox API (e.g. https://proxmox.example.com:8006/api2/json)."
  type        = string
}

variable "pm_tls_insecure" {
  description = "Allow self-signed certificates when talking to Proxmox."
  type        = bool
  default     = true
}

variable "pm_api_token_id" {
  description = "Proxmox API token ID (format user@realm!token)."
  type        = string
}

variable "pm_api_token_secret" {
  description = "Proxmox API token secret."
  type        = string
  sensitive   = true
}

variable "proxmox_ssh_username" {
  description = "SSH username used by the provider for operations requiring SSH (defaults to root)."
  type        = string
  default     = "root"
}

variable "proxmox_pve_node_name" {
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

variable "cluster_endpoint" {
  description = "Kubernetes API server endpoint"
  type        = string
}

variable "cluster_vip" {
  description = "Virtual IP for the cluster control plane"
  type        = string
}

variable "cluster_node_network" {
  description = "Network CIDR for cluster nodes"
  type        = string
  default     = "10.5.0.0/16"
}

variable "cluster_node_network_gateway" {
  description = "Gateway for the cluster node network"
  type        = string
  default     = "10.5.0.1"
}

variable "cluster_node_network_first_controller_hostnum" {
  description = "First host number for controller nodes"
  type        = number
  default     = 11
}

variable "cluster_node_network_first_worker_hostnum" {
  description = "First host number for worker nodes"
  type        = number
  default     = 21
}

variable "controller_count" {
  description = "Number of controller nodes"
  type        = number
  default     = 3
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2
}

variable "prefix" {
  description = "Prefix for VM names"
  type        = string
  default     = "talos"
}

variable "talos_version" {
  description = "Talos version (will be set by do script)"
  type        = string
  default     = "1.11.2"
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.32.1"
}

# Tailscale integration
variable "headscale_api_key" {
  description = "Headscale API key for generating pre-auth keys."
  type        = string
  sensitive   = true
  
  validation {
    condition     = var.headscale_api_key != ""
    error_message = "Headscale API key is required for Tailscale functionality."
  }
}

variable "headscale_user" {
  description = "Headscale user for pre-auth key generation."
  type        = string
  default     = "agentydragon"
}

variable "headscale_login_server" {
  description = "Headscale login server URL."
  type        = string
  default     = "https://agentydragon.com:8080"
}
