locals {
  function_app_name = "${var.name_prefix}-func"
  admin_app_name    = "${var.name_prefix}-admin"

  # The Function App clears the "api" route prefix (see src/UrlShortener.Functions/host.json),
  # so a short link is just the app's hostname and the code.
  short_link_base_url = "https://${azurerm_linux_function_app.main.default_hostname}"

  # Each app's SCM site, which the publish profiles deploy to. Azure names it
  # <app>.scm.<domain>; Locally names it <app>-scm.<domain>.
  scm_separator     = var.environment_is_locally ? "-scm." : ".scm."
  function_scm_host = replace(azurerm_linux_function_app.main.default_hostname, "/^([^.]+)\\./", "$1${local.scm_separator}")
  admin_scm_host    = replace(azurerm_linux_web_app.admin.default_hostname, "/^([^.]+)\\./", "$1${local.scm_separator}")

  # The directory's sign-out endpoint, which the admin site's Sign out link
  # ends at.
  entra_sign_out_url = "${var.authority_host}/${data.azuread_client_config.current.tenant_id}/oauth2/v2.0/logout"

  # The source for both apps. Any change to it (other than build output)
  # republishes them - see 9-deploy.tf.
  src_dir = abspath("${path.module}/../../src")
  src_files = [
    for f in fileset(local.src_dir, "**") : f
    if !strcontains(f, "/bin/") && !strcontains(f, "/obj/")
  ]
  source_hash = substr(sha1(join(",", [for f in local.src_files : "${f}:${filesha1("${local.src_dir}/${f}")}"])), 0, 12)

  build_dir = abspath("${path.module}/../../.build")

  # Locally exposes the Flexible Server on a dynamic port encoded in the fqdn
  # ("host:port"), whereas Azure returns a bare hostname served on 5432. Split
  # the fqdn so the apps always get a plain host plus an explicit port that's
  # correct in both places.
  pg_fqdn = azurerm_postgresql_flexible_server.main.fqdn
  pg_host = split(":", local.pg_fqdn)[0]
  pg_port = length(split(":", local.pg_fqdn)) > 1 ? split(":", local.pg_fqdn)[1] : "5432"

  # Settings both apps share: where the database is, and which identity to
  # authenticate to it and to Application Insights as.
  shared_app_settings = {
    # There's no PGPASSWORD: the apps fetch an Entra access token for the
    # managed identity and present that as the password.
    PGHOST     = local.pg_host
    PGPORT     = local.pg_port
    PGDATABASE = azurerm_postgresql_flexible_server_database.links.name
    PGUSER     = azurerm_user_assigned_identity.main.name

    # Selects the user-assigned identity the managed identity endpoint issues
    # tokens for.
    AZURE_CLIENT_ID = azurerm_user_assigned_identity.main.client_id
  }
}
