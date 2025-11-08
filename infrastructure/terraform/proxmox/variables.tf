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

variable "cluster_nodes" {
  description = <<EOT
Map of cluster node definitions. Keys should be logical node names. Each value controls cloning parameters.
EOT
  type = map(object({
    vm_id       = number
    name        = string
    role        = string
    target_node = string
    pool        = optional(string)
    sockets     = optional(number)
    cores       = number
    memory_mb   = number
    disk_gb     = number
    mac_address = string
    bridge      = string
    vlan_tag    = optional(number)
    ipconfig0   = string
    tags        = optional(list(string))
  }))
  default = {}
}

variable "talos_disk_storage" {
  description = "Proxmox storage ID where VM disks should live (e.g. local-zfs)."
  type        = string
}

variable "talos_iso_path" {
  description = "Storage path (e.g., local:iso/talos.iso) for the Talos ISO already uploaded to Proxmox."
  type        = string

  validation {
    condition     = can(regex("^.+:.+$", var.talos_iso_path))
    error_message = "talos_iso_path must follow the <storage>:<path> format (e.g., local:iso/talos.iso)."
  }
}

variable "talos_iso_url" {
  description = "Remote URL from which to download the Talos ISO if it is missing from Proxmox storage."
  type        = string
}

variable "talos_template_node" {
  description = "Proxmox node on which ISO downloads should occur."
  type        = string
}

variable "proxmox_ssh_username" {
  description = "SSH username used by the provider for operations requiring SSH (defaults to root)."
  type        = string
  default     = "root"
}
