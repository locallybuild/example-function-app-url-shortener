# ---------------------------------------------------------------------------
# Log Analytics - where Application Insights stores the apps' telemetry.
# ---------------------------------------------------------------------------
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.name_prefix}-logs"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags

  # On Azure, Log Analytics is billed per GB ingested (beyond a free 5 GB a
  # month), so a cap stops a burst of traffic or a noisy log level running up
  # a bill. Once it's reached, ingestion stops until the next day.
  daily_quota_gb = var.log_analytics_daily_quota_gb
}

# ---------------------------------------------------------------------------
# Application Insights - workspace-based, shared by the Function App and the
# admin site. Both send their requests, dependencies (the PostgreSQL calls) and
# custom events here:
#
#   LinkFollowed / LinkNotFound - from the Function App, one per redirect
#   LinkCreated / LinkDeleted   - from the admin site
#
# Within the Locally Dashboard these can be queried using:
#   AppEvents | order by TimeGenerated desc
#
# Local authentication is disabled: the instrumentation key in the connection
# string only says where to send telemetry. Each batch must also carry an
# Entra access token for an identity holding the Monitoring Metrics Publisher
# role.
# ---------------------------------------------------------------------------
resource "azurerm_application_insights" "main" {
  name                         = "${var.name_prefix}-insights"
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  workspace_id                 = azurerm_log_analytics_workspace.main.id
  application_type             = "web"
  local_authentication_enabled = false
  tags                         = var.tags
}

resource "azurerm_role_assignment" "telemetry" {
  scope                = azurerm_application_insights.main.id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = azurerm_user_assigned_identity.main.principal_id
  principal_type       = "ServicePrincipal"
}
