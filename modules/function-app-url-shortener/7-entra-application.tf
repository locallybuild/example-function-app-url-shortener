data "azuread_client_config" "current" {}

# ---------------------------------------------------------------------------
# App registration - the identity App Service signs admins in with.
#
# App Service Authentication on the admin site (auth_settings_v2 in
# 8-admin-app.tf) is configured entirely from this registration. Against
# Locally, sign-in happens in Locally's Directory Emulator, where you pick one
# of the seeded users; against Azure, it's Microsoft Entra ID.
#
# Signing in isn't enough on its own: the admin site also requires the Admin
# app role below, which is assigned to var.admin_principal_ids and to whoever
# runs Terraform.
# ---------------------------------------------------------------------------
resource "random_uuid" "admin_role" {}

resource "azuread_application" "admin" {
  display_name = "${var.name_prefix} admin"
  owners       = [data.azuread_client_config.current.object_id]

  # Arrives in the signed-in user's "roles" claim when they hold it, which the
  # admin site checks for on every page.
  app_role {
    id           = random_uuid.admin_role.result
    value        = "Admin"
    display_name = "Admin"
    description  = "Add and remove short links."
    # "Application" as well as "User", so a service principal can hold it -
    # such as Locally's Default Identity, which `locally run` deploys as.
    allowed_member_types = ["User", "Application"]
    enabled              = true
  }

  web {
    implicit_grant {
      # App Service reads the user's identity from the ID token.
      id_token_issuance_enabled = true
    }
  }

  lifecycle {
    # Managed by azuread_application_redirect_uris below.
    ignore_changes = [web[0].redirect_uris]
  }
}

# The redirect URIs: App Service's sign-in callback, and the page signing out
# returns to (Entra only returns to a registered address). They're added once
# the admin site exists, as they're built from the site's hostname.
resource "azuread_application_redirect_uris" "admin" {
  application_id = azuread_application.admin.id
  type           = "Web"
  redirect_uris = [
    "https://${azurerm_linux_web_app.admin.default_hostname}/.auth/login/aad/callback",
    "https://${azurerm_linux_web_app.admin.default_hostname}/signed-out",
  ]
}

resource "azuread_service_principal" "admin" {
  client_id = azuread_application.admin.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

# Who gets the Admin role: whoever runs Terraform (against Locally, that's the
# Default Identity on the sign-in page), and var.admin_principal_ids. Assigning
# it to a group gives it to the group's members.
resource "azuread_app_role_assignment" "admin" {
  for_each = toset(concat([data.azuread_client_config.current.object_id], var.admin_principal_ids))

  app_role_id         = random_uuid.admin_role.result
  principal_object_id = each.value
  resource_object_id  = azuread_service_principal.admin.object_id
}

# The client secret App Service redeems the sign-in code with.
resource "azuread_application_password" "admin" {
  application_id = azuread_application.admin.id
  display_name   = "App Service Authentication"
}
