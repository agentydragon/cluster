# PowerDNS bootstrap secrets are handled by ExternalSecrets Operator password generator
# This avoids circular dependencies and keeps PowerDNS independent of Vault
# ESO Password Generator → K8s Secret → PowerDNS (no Vault needed)