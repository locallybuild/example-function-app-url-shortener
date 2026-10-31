# ---------------------------------------------------------------------------
# User-Assigned Managed Identity - the identity both apps authenticate as.
#
# It's the PostgreSQL server's Entra administrator (3-postgresql.tf) and holds
# the role that lets it send telemetry to Application Insights
# (4-monitoring.tf), so neither app has a database password or an
# instrumentation key that works on its own.
#
# A user-assigned identity exists independently of the apps, so both grants
# are in place before either app starts and connects.
# ---------------------------------------------------------------------------
resource "azurerm_user_assigned_identity" "main" {
  name                = "${var.name_prefix}-id"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = var.tags
}

# The tenant the identity lives in, needed to register it as the PostgreSQL
# Entra administrator.
data "azurerm_client_config" "current" {}
