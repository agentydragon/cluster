# LAYER 2 DATA SOURCES
# References to infrastructure layer outputs

data "terraform_remote_state" "infrastructure" {
  backend = "local"
  config = {
    path = "../01-infrastructure/terraform.tfstate"
  }
}