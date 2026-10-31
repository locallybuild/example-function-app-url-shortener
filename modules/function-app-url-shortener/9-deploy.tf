# ---------------------------------------------------------------------------
# Deploy the code, the way you would from Visual Studio: `dotnet publish` with
# a publish profile, signing in to the app's SCM site with its publishing
# credentials (the user and password in the app's publish profile).
#
# The publish profile (Properties/PublishProfiles/ZipDeploy.pubxml in each
# project) uses the ZipDeploy method, which is how Linux apps are published:
# MSDeploy is Windows-only on both ends. The profile reads the SCM host and the
# credentials from the environment, so the password never appears on a command
# line.
#
# Because the credentials are sensitive, Terraform hides the publish's output.
# It's written to .build/<app>-publish.log instead, and the publish only counts
# as done if the log says the deployment succeeded (a publish profile the SDK
# doesn't recognise builds the app and quietly deploys nothing).
#
# A change to anything under src/ changes local.source_hash, which republishes
# both apps on the next apply.
# ---------------------------------------------------------------------------
# The Function App is published with `dotnet build -p:DeployOnBuild=true`
# rather than `dotnet publish`: the CLI's publish only runs the deploy step for
# ASP.NET Core projects (see the comments in its publish profile).
resource "terraform_data" "publish_function" {
  triggers_replace = [
    azurerm_linux_function_app.main.id,
    local.source_hash,
  ]

  provisioner "local-exec" {
    working_dir = local.src_dir
    environment = {
      DeployHost     = local.function_scm_host
      DeployUserName = azurerm_linux_function_app.main.site_credential[0].name
      DeployPassword = azurerm_linux_function_app.main.site_credential[0].password
    }
    command = <<-EOT
      set -eu
      mkdir -p ${local.build_dir}
      dotnet build UrlShortener.Functions -c Release -p:DeployOnBuild=true -p:PublishProfile=ZipDeploy > ${local.build_dir}/${local.function_app_name}-publish.log 2>&1
      grep -q 'Zip Deployment succeeded' ${local.build_dir}/${local.function_app_name}-publish.log
    EOT
  }
}

resource "terraform_data" "publish_admin" {
  triggers_replace = [
    azurerm_linux_web_app.admin.id,
    local.source_hash,
  ]

  provisioner "local-exec" {
    working_dir = local.src_dir
    environment = {
      DeployHost     = local.admin_scm_host
      DeployUserName = azurerm_linux_web_app.admin.site_credential[0].name
      DeployPassword = azurerm_linux_web_app.admin.site_credential[0].password
    }
    command = <<-EOT
      set -eu
      mkdir -p ${local.build_dir}
      dotnet publish UrlShortener.Admin -c Release -p:PublishProfile=ZipDeploy > ${local.build_dir}/${local.admin_app_name}-publish.log 2>&1
      grep -q 'Zip Deployment succeeded' ${local.build_dir}/${local.admin_app_name}-publish.log
    EOT
  }

  # Both projects build the shared UrlShortener.Data project; publishing them
  # one after the other keeps the two builds from writing its output at once.
  depends_on = [terraform_data.publish_function]
}
