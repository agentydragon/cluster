# Main entrypoint for Talos Kubernetes cluster infrastructure
# This module provisions a complete Kubernetes cluster on Proxmox using Talos Linux

# Core cluster components are defined in:
# - nodes.tf: VM definitions and Talos cluster configuration
# - cilium.tf: CNI networking
# - flux.tf: GitOps with Flux CD
# - sealed-secrets-*.tf: Secret management
# - providers.tf: Terraform provider configurations
# - locals.tf: Shared configuration values