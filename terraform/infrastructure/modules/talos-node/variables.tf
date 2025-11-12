# Node configuration
variable "node_name" {
  description = "Name of the node (e.g., c0, w0)"
  type        = string
}

variable "node_type" {
  description = "Type of node: controller or worker"
  type        = string
  validation {
    condition     = contains(["controller", "worker"], var.node_type)
    error_message = "node_type must be either 'controller' or 'worker'."
  }
}

variable "vm_id" {
  description = "Proxmox VM ID"
  type        = number
}

variable "ip_address" {
  description = "Static IP address for this node"
  type        = string
}

variable "gateway" {
  description = "Network gateway"
  type        = string
}

# Proxmox configuration
variable "proxmox_node_name" {
  description = "Proxmox node name"
  type        = string
}

variable "prefix" {
  description = "VM name prefix"
  type        = string
  default     = "talos"
}

# Talos configuration
variable "talos_version" {
  description = "Talos version"
  type        = string
}

variable "cluster_name" {
  description = "Talos cluster name"
  type        = string
}

variable "cluster_endpoint" {
  description = "Kubernetes API server endpoint"
  type        = string
}

variable "cluster_vip" {
  description = "Virtual IP for cluster control plane (only used for controllers)"
  type        = string
  default     = ""
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
}

variable "machine_secrets" {
  description = "Talos machine secrets"
  type        = any
  sensitive   = true
}

# Global configuration passed from root
variable "global_config" {
  description = "Global configuration object"
  type = object({
    headscale_api_key      = string
    headscale_login_server = string
  })
  sensitive = true
}
