# Headscale API key from keyring
data "keyring_secret" "headscale_api_key" {
  name = "headscale-api-key"
}

locals {
  headscale_api_key = data.keyring_secret.headscale_api_key.secret
}