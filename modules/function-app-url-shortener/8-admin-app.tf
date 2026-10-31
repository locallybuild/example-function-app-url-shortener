# ---------------------------------------------------------------------------
# App Service - the admin site, an ASP.NET Core app for adding and removing
# links and seeing how often each one has been followed.
#
# It shares the plan, the identity, the database and Application Insights with
# the Function App. Like the Function App it's created empty, and 9-deploy.tf
# publishes the code into it.
#
# App Service Authentication signs admins in before a request reaches the app,
# using the app registration in 7-entra-application.tf. The app does no sign-in
# of its own: it reads who the user is from the X-MS-CLIENT-PRINCIPAL header
# App Service passes it, and checks they hold the Admin app role.
# ---------------------------------------------------------------------------
resource "azurerm_linux_web_app" "admin" {
  name                = local.admin_app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_service_plan.main.location
  service_plan_id     = azurerm_service_plan.main.id
  https_only          = true
  tags                = var.tags

  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = true

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.main.id]
  }

  site_config {
    health_check_path                 = "/healthz"
    health_check_eviction_time_in_min = 2

    application_stack {
      dotnet_version = "10.0"
    }
  }

  app_settings = merge(local.shared_app_settings, {
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.main.connection_string

    # App Service terminates TLS in front of the app. This has ASP.NET Core
    # honour X-Forwarded-Proto, so redirects stay on https. Azure sets it for
    # Linux .NET apps already; Locally doesn't.
    ASPNETCORE_FORWARDEDHEADERS_ENABLED = "true"

    # The app registration's client secret, which auth_settings_v2 refers to
    # by this setting's name.
    MICROSOFT_PROVIDER_AUTHENTICATION_SECRET = azuread_application_password.admin.value

    # Where the Sign out link sends you, once App Service has ended its own
    # session: the directory's sign-out, which ends the directory's session
    # too.
    ENTRA_SIGN_OUT_URL = local.entra_sign_out_url

    # Shown next to each link, so you can copy the short URL.
    SHORT_LINK_BASE_URL = local.short_link_base_url
  })

  auth_settings_v2 {
    auth_enabled           = true
    require_authentication = true
    unauthenticated_action = "RedirectToLoginPage"
    default_provider       = "azureactivedirectory"

    # Reachable without signing in: App Service's health check, and the page
    # signing out takes you to.
    excluded_paths = ["/healthz", "/signed-out"]

    active_directory_v2 {
      client_id                  = azuread_application.admin.client_id
      client_secret_setting_name = "MICROSOFT_PROVIDER_AUTHENTICATION_SECRET"
      tenant_auth_endpoint       = "${var.authority_host}/${data.azuread_client_config.current.tenant_id}/v2.0"

      # Signing out (/.auth/logout) ends the admin site's session, but not the
      # directory's own, so the next sign-in would quietly reuse whoever signed
      # in last. Asking the directory to show its account picker every time
      # means signing out, then in again, lets you pick someone else.
      login_parameters = {
        prompt = "select_account"
      }
    }

    login {
      # Signing out goes on to the directory's own sign-out (see Shared/_Layout.cshtml).
      allowed_external_redirect_urls = [local.entra_sign_out_url]
    }
  }

  depends_on = [
    azurerm_postgresql_flexible_server_active_directory_administrator.app,
    azurerm_postgresql_flexible_server_firewall_rule.azure_services,
    azurerm_role_assignment.telemetry,
  ]
}
