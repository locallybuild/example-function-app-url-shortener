output "short_link_base_url" {
  description = "Short links resolve under this URL: <base>/<code> redirects to the link's target."
  value       = module.function-app-url-shortener.short_link_base_url
}

output "admin_url" {
  description = "The admin site, where links are added and removed."
  value       = module.function-app-url-shortener.admin_url
}

output "admin_application_client_id" {
  description = "The client ID of the app registration admins sign in with."
  value       = module.function-app-url-shortener.admin_application_client_id
}

output "postgresql_fqdn" {
  description = "The PostgreSQL Flexible Server hostname both apps connect to."
  value       = module.function-app-url-shortener.postgresql_fqdn
}
