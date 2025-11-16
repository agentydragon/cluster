# Version constraints inherited from /terraform/versions.tf


# Create admin groups for each service
resource "authentik_group" "harbor_admins" {
  name         = "harbor-admins"
  is_superuser = false
}

resource "authentik_group" "gitea_admins" {
  name         = "gitea-admins"
  is_superuser = false
}

resource "authentik_group" "matrix_admins" {
  name         = "matrix-admins"
  is_superuser = false
}

# Create custom property mappings for OIDC
resource "authentik_property_mapping_provider_scope" "groups" {
  name        = "Groups Mapping"
  scope_name  = "groups"
  description = "Groups scope for SSO services"
  expression  = "return {'groups': [group.name for group in user.ak_groups.all()]}"
}

resource "authentik_property_mapping_provider_scope" "preferred_username" {
  name        = "Preferred Username Mapping"
  scope_name  = "openid"
  description = "Preferred username mapping for SSO services"
  expression  = "return {'preferred_username': request.user.username}"
}

# Create a custom user for automated provisioning (optional)
resource "authentik_user" "automation" {
  username = "automation"
  name     = "SSO Automation User"
  email    = "automation@test-cluster.agentydragon.com"

  # Add to all admin groups
  groups = [
    authentik_group.harbor_admins.id,
    authentik_group.gitea_admins.id,
    authentik_group.matrix_admins.id
  ]

  is_superuser = false
  is_staff     = false
  is_active    = true
}
