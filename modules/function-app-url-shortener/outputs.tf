output "short_link_base_url" {
  description = "Short links resolve under this URL: <base>/<code> redirects to the link's target."
  value       = local.short_link_base_url
}

output "admin_url" {
  description = "The admin site, where links are added and removed."
  value       = "https://${azurerm_linux_web_app.admin.default_hostname}"
}

output "admin_application_client_id" {
  description = "The client ID of the app registration admins sign in with."
  value       = azuread_application.admin.client_id
}

output "postgresql_fqdn" {
  description = "The PostgreSQL Flexible Server hostname both apps connect to."
  value       = azurerm_postgresql_flexible_server.main.fqdn
}

output "application_insights_name" {
  description = "The Application Insights resource both apps send telemetry to."
  value       = azurerm_application_insights.main.name
}

output "resource_group" {
  description = "The resource group containing the deployed resources."
  value       = azurerm_resource_group.main.name
}
