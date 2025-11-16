# STORAGE MODULE VARIABLES

variable "csi_config" {
  description = "CSI configuration from pve-auth module"
  type = object({
    url          = string
    insecure     = bool
    token_id     = string
    token_secret = string
    region       = string
    token        = string
  })
  sensitive = true
}