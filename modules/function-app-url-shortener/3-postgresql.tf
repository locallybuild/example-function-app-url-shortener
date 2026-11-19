# ---------------------------------------------------------------------------
# Azure Database for PostgreSQL Flexible Server - where the links live.
#
# The server requires an administrator login, so Terraform generates a random
# password for it. Neither app uses it: they sign in with the managed
# identity's Entra access token instead (see the Entra administrator below).
# ---------------------------------------------------------------------------
resource "random_password" "pg_admin" {
  length           = 24
  special          = true
  override_special = "!#%*-_"
}

resource "azurerm_postgresql_flexible_server" "main" {
  name                   = "${var.name_prefix}-pg"
  resource_group_name    = azurerm_resource_group.main.name
  location               = azurerm_resource_group.main.location
  version                = "18"
  sku_name               = "B_Standard_B1ms"
  storage_mb             = 32768
  administrator_login    = "pgadmin"
  administrator_password = random_password.pg_admin.result
  tags                   = var.tags

  authentication {
    active_directory_auth_enabled = true
    password_auth_enabled         = true
    tenant_id                     = data.azurerm_client_config.current.tenant_id
  }

  # Azure picks an availability zone when none is given, and the server can't
  # be moved out of it afterwards, so don't try to reset it on later applies.
  lifecycle {
    ignore_changes = [zone]
  }
}

# ---------------------------------------------------------------------------
# Entra administrator - makes the managed identity the server's admin.
#
# The identity's name becomes its PostgreSQL login (the apps' PGUSER), and the
# apps present an Entra access token for it in place of a password.
# ---------------------------------------------------------------------------
resource "azurerm_postgresql_flexible_server_active_directory_administrator" "app" {
  server_name         = azurerm_postgresql_flexible_server.main.name
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  object_id           = azurerm_user_assigned_identity.main.principal_id
  principal_name      = azurerm_user_assigned_identity.main.name
  principal_type      = "ServicePrincipal"
}

resource "azurerm_postgresql_flexible_server_database" "links" {
  name      = "links"
  server_id = azurerm_postgresql_flexible_server.main.id
}

# ---------------------------------------------------------------------------
# Firewall rule - lets the apps reach the server.
#
# The server is on a public endpoint, and its firewall refuses everything by
# default. The 0.0.0.0 rule is Azure's special case for "allow Azure services",
# which is where the apps' outbound connections come from. That's any Azure
# customer's services, not just yours, so it's signing in - which needs the
# managed identity's token - that keeps everyone else out. For a server with
# no public endpoint, put the apps and the server in a virtual network instead.
# ---------------------------------------------------------------------------
resource "azurerm_postgresql_flexible_server_firewall_rule" "azure_services" {
  name             = "allow-azure-services"
  server_id        = azurerm_postgresql_flexible_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}
