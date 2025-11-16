# LAYER 3 DATA SOURCES
# References to infrastructure and services layer outputs

data "terraform_remote_state" "infrastructure" {
  backend = "local"
  config = {
    path = "../01-infrastructure/terraform.tfstate"
  }
}

data "terraform_remote_state" "services" {
  backend = "local"
  config = {
    path = "../02-services/terraform.tfstate"
  }
}