# ---------------------------------------------------------------------------
# App Service Plan - hosts both the Function App and the admin site.
# ---------------------------------------------------------------------------
resource "azurerm_service_plan" "main" {
  name                = "${var.name_prefix}-plan"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = var.service_plan_sku
  tags                = var.tags
}

# ---------------------------------------------------------------------------
# The Function App - serves the short links.
#
# GET /<code> looks the code up in PostgreSQL, counts the click and redirects
# to the target. host.json clears the "api" route prefix so links are as short
# as they can be.
#
# Terraform creates the app empty; 9-deploy.tf publishes the code into it with
# its publishing credentials, which is why basic authentication for publishing
# stays enabled.
# ---------------------------------------------------------------------------
resource "azurerm_linux_function_app" "main" {
  name                = local.function_app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.main.id
  https_only          = true
  tags                = var.tags

  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key

  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = true

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.main.id]
  }

  site_config {
    always_on = true

    application_insights_connection_string = azurerm_application_insights.main.connection_string

    application_stack {
      dotnet_version              = "10.0"
      use_dotnet_isolated_runtime = true
    }
  }

  app_settings = merge(local.shared_app_settings, {
    FUNCTIONS_WORKER_RUNTIME = "dotnet-isolated"

    # The Functions host sends its own telemetry too. With local authentication
    # disabled on Application Insights, this tells it which identity to get a
    # token as (the worker's own telemetry is configured in Program.cs).
    APPLICATIONINSIGHTS_AUTHENTICATION_STRING = "Authorization=AAD;ClientId=${azurerm_user_assigned_identity.main.client_id}"
  })

  # The identity must be the database administrator, and hold its telemetry
  # role, before the app starts and connects.
  depends_on = [
    azurerm_postgresql_flexible_server_active_directory_administrator.app,
    azurerm_postgresql_flexible_server_firewall_rule.azure_services,
    azurerm_role_assignment.telemetry,
  ]
}
