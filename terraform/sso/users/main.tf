# Data source for authentik Admins group
data "authentik_group" "admins" {
  name = "authentik Admins"
}

# Create agentydragon user
resource "authentik_user" "agentydragon" {
  username = "agentydragon"
  name     = "Rai"
  email    = "agentydragon@gmail.com"
  password = var.user_password
  groups   = [data.authentik_group.admins.id]
}
